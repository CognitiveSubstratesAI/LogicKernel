# UPSTREAM: swipl-devel src/pl-read.c @ bae881a2
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2026, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# THE READER (R1; decided by the user, 2026-10-07: SWI-7's default syntax only, refused constructs
# an explicit error). Since R1c the SCANNER: the Unicode classifiers over the map (src/pl-umap.jl),
# the raw read of one term's text from a stream (comments dropped, positions kept, `raw_read`), the
# syntax errors with their location, numbers (`str_number`: every base syntax, digit groups,
# `1r3` rationals, floats with `Inf` and `NaN`), escapes and quoted text, the variable table, and
# the tokeniser (`get_token`). R1d adds the parser (`complex_term`, `simple_term`, `build_term`)
# and `read_term/2,3`.

# ── the Unicode classifiers (pl-read.c) ─────────────────────────────────────────────────────────

# PORT: pl-read.c CharTypeA
"The type of ASCII code `c` (`_PL_char_types`) (pl-read.c)."
@inline CharTypeA(c::Int)::Int = Int(_PL_char_types[(c & 0x7f) + 1])

# PORT: pl-read.c pl_cat_is_id_start
"Does the category start an identifier (pl-read.c)?"
pl_cat_is_id_start(cat::u_category)::Bool =
    cat == U_CAT_ID_START_ATOM || cat == U_CAT_ID_START_VARIABLE

# PORT: pl-read.c pl_cat_is_id_continue
"Does the category continue an identifier (pl-read.c)?"
function pl_cat_is_id_continue(cat::u_category)::Bool
    return cat == U_CAT_ID_CONTINUE || cat == U_CAT_ID_START_ATOM ||
           cat == U_CAT_ID_START_VARIABLE || cat == U_CAT_DECIMAL ||
           cat == U_CAT_ID_CONTINUE_SOLO
end

# PORT: pl-read.c pl_cat_is_solo
"Is the category a solo character's (pl-read.c)?"
pl_cat_is_solo(cat::u_category)::Bool =
    cat == U_CAT_SOLO || cat == U_CAT_ID_CONTINUE_SOLO || cat == U_CAT_PATTERN_SYNTAX

# PORT: pl-read.c PlCatW
"The syntax category of code point `c` (pl-read.c)."
@inline PlCatW(c::Int)::u_category = U_CAT_OF(uflagsRaw(c))

# PORT: pl-read.c PlBlankW
"Is `c` layout (pl-read.c)?"
PlBlankW(c::Int)::Bool =
    (c % UInt32) < 0x80 ? CharTypeA(c) == SP : PlCatW(c) == U_CAT_LAYOUT
# PORT: pl-read.c PlUpperW
"Does `c` start a variable (pl-read.c)?"
PlUpperW(c::Int)::Bool =
    (c % UInt32) < 0x80 ? CharTypeA(c) == UC : PlCatW(c) == U_CAT_ID_START_VARIABLE
# PORT: pl-read.c PlIdStartW
"Does `c` start an identifier (pl-read.c)?"
PlIdStartW(c::Int)::Bool =
    if (c % UInt32) < 0x80
        (isLower(c) || isUpper(c) || c == Int('_'))
    else
        pl_cat_is_id_start(PlCatW(c))
    end
# PORT: pl-read.c PlIdContW
"Does `c` continue an identifier (pl-read.c)?"
PlIdContW(c::Int)::Bool =
    (c % UInt32) < 0x80 ? CharTypeA(c) >= UC : pl_cat_is_id_continue(PlCatW(c))
# PORT: pl-read.c PlSymbolW
"Is `c` a symbol character: ASCII only (pl-read.c)?"
PlSymbolW(c::Int)::Bool = (c % UInt32) < 0x80 ? CharTypeA(c) == SY : false
# PORT: pl-read.c PlDecimalW
"Is `c` a decimal digit, in any script (pl-read.c)?"
PlDecimalW(c::Int)::Bool =
    (c % UInt32) < 0x80 ? CharTypeA(c) == DI : PlCatW(c) == U_CAT_DECIMAL
# PORT: pl-read.c PlPunctW
"Is `c` ASCII punctuation (pl-read.c)?"
PlPunctW(c::Int)::Bool = (c % UInt32) < 0x80 ? CharTypeA(c) == PU : false
# PORT: pl-read.c PlSoloW
"Is `c` a solo character (pl-read.c)?"
PlSoloW(c::Int)::Bool = (c % UInt32) < 0x80 ? CharTypeA(c) == SO : pl_cat_is_solo(PlCatW(c))
# PORT: pl-read.c PlInvalidW
"Is `c` no Prolog character at all (pl-read.c)?"
PlInvalidW(c::Int)::Bool = PlCatW(c) == U_CAT_OTHER

# PORT: pl-read.c is_eol_char
"Is `c` one of the seven line terminators (pl-read.c)?"
function is_eol_char(c::Int)::Bool
    return c == Int('\n') || c == 0x0b || c == 0x0c || c == Int('\r') || c == 0x0085 ||
           c == 0x2028 || c == 0x2029
end

# PORT: pl-read.c PL_ctype_flags
"The POSIX class bits (`PL_CTYPE_*`) of `chr` (pl-read.c)."
PL_ctype_flags(chr::Int)::UInt16 = uctypeFlagsW(chr)

# PORT: pl-read.c PL_wcwidth
"The display width of `chr`: -1 not printable, 0 zero-width, 1 or 2 (pl-read.c)."
PL_wcwidth(chr::Int)::Int = Int((uflagsRaw(chr) >> 4) & 0x3) - 1

# PORT: pl-read.c decimal_weight
"The value of the decimal digit `code`, in any script (pl-read.c)."
function decimal_weight(code::Int)::Int
    (code >= Int('0') && code <= Int('9')) && return code - Int('0')
    s = 1
    e = length(decimal_bases) + 1
    m = s + (e - s) ÷ 2
    while e > s
        if code < decimal_bases[m]
            e = (e == m ? e - 1 : m)
            m = s + (e - s) ÷ 2
        elseif code > decimal_bases[m] + 10
            s = (s == m ? s + 1 : m)
            m = s + (e - s) ÷ 2
        else
            return code - decimal_bases[m]
        end
    end
    @assert false "decimal_weight: $code is not a decimal digit"
    return -1
end

# PORT: pl-read.c is_bidi_override
"Is `c` a bidi override or isolate, which the reader always refuses (pl-read.c)?"
is_bidi_override(c::Int)::Bool =
    (c >= 0x202A && c <= 0x202E) || (c >= 0x2066 && c <= 0x2069)

# ── the variable table (pl-read.c) ──────────────────────────────────────────────────────────────

# PORT: pl-read.c variable
# DIVERGES: the name is its own byte vector, where upstream points into `var_name_buffer`;
# `variable` is a term reference (0: none yet, as upstream), `signature` the index the table gives.
"A variable of the term being read (pl-read.c): its name, its term reference, how often it occurs."
mutable struct variable
    name::Vector{UInt8}             # Name of the variable
    namelen::Int                    # length of the name
    variable::term_t                # Term-reference to the variable
    times::Int                      # Number of occurences
    hash_next::Int                  # Offset for next with same hash
    signature::Int                  # Pseudo atom (the index, valVarInfo)
    labeled::Bool                   # Used in X{= : Value}
end

# PORT: pl-read.c var_table
# DIVERGES: the variables are a vector of records, where upstream keeps them, and their names,
# in two growing buffers.
"The variables of the term being read and their hash table (pl-read.c)."
mutable struct var_table
    var_buffer::Vector{variable}    # array of struct variables
    var_hash_size::Int              # #buckets
    var_buckets::Vector{Int}        # hash table
end
var_table() = var_table(variable[], 0, Int[])

# ── the read data (pl-read.c) ───────────────────────────────────────────────────────────────────

# PORT: pl-read.c token_type
"A token's type (pl-read.c)."
@enum token_type::UInt8 begin
    TK_FUNCTOR = 0          # name of a functor (atom, followed by '(')
    TK_DICT                 # name of a dict class (atom, followed by '{')
    TK_QNAME                # quoted name
    TK_NAME                 # ordinary name
    TK_VCLASS_DICT          # variable name followed by '{'
    TK_VARIABLE             # variable name
    TK_VOID_DICT            # void variable followed by '{'
    TK_VOID                 # void variable
    TK_NUMBER               # integer or float
    TK_STRING               # "string"
    TK_PUNCTUATION          # punctuation character
    TK_FULLSTOP             # Prolog end of clause
    TK_QQ_OPEN              # "{|" of {|Syntax||Quotation|} stuff
    TK_QQ_BAR               # "||" of {|Syntax||Quotation|} stuff
    TK_BLOB                 # <type>( of a blob, see blob/2
end

# PORT: pl-read.c token
# DIVERGES: the value's alternatives are fields, where upstream holds a union; a string's value is
# the term (`term_value`), where upstream holds a term reference; `variable` is the variable's
# index in the variable table.
"The current token (pl-read.c): its type, its character positions and its value."
mutable struct token{T}
    type::token_type                # type of token
    start::Int64                    # start-position
    end_::Int64                     # end-position
    number::number                  # int or float
    atom::Union{Nothing, T}         # atom value
    term_value::Union{Nothing, T}   # term (list or string)
    character::Int                  # a punctuation character (TK_PUNCTUATION)
    variable::Int                   # a variable record (TK_VARIABLE)
end
token{T}() where {T} = token{T}(TK_NAME, 0, 0, number(), nothing, nothing, 0, 0)

# PORT: pl-read.c FASTBUFFERSIZE
"The read buffer's first size (pl-read.c)."
const FASTBUFFERSIZE = 256

# PORT: pl-read.c read_buffer
# DIVERGES: one byte vector `base` with indices, where upstream starts in a 256-byte `fast` array
# and moves to malloc()ed memory (`growToBuffer`).
"The text of the term being read, as read (pl-read.c)."
mutable struct read_buffer
    size::Int                       # current size of read buffer
    base::Vector{UInt8}             # base of read buffer
    here::Int                       # current position in read buffer
    end_::Int                       # end of the valid buffer
    stream::IOSTREAM                # stream we are reading from
end

# PORT: pl-read.c RD_MAGIC
"The read data's magic number (pl-read.c)."
const RD_MAGIC = 0xefebe128

# PORT: pl-read.c read_data
# DIVERGES: positions in the buffer are indices into `_rb.base`; `module_` is the module's index;
# `ld` is the engine's local data, which upstream reaches through `LD`. NOT PORTED (R1d): the
# term stack and the operator queues; quasi-quotations; the character conversion table
# (`char_conversion/2`).
"Everything a read of one term needs (pl-read.c `read_data`)."
mutable struct read_data{T}
    here::Int                       # current character
    base::Int                       # base of clause
    end_::Int                       # end of the clause
    token_start::Int                # start of most recent read token
    token::token{T}                 # current token
    _unget::Bool                    # unget_token()
    magic::UInt32                   # RD_MAGIC
    start_of_term::source_location{T}   # Position of start of term
    posp::Int                       # position pointer
    posi::Int                       # position number
    module_::Int                    # Current source module
    flags::UInt32                   # Module syntax flags (M_*)
    var_prefix::Int                 # Variable prefix char (0: none)
    styleCheck::Int                 # style-checking mask
    on_error::Symbol                # Handling of syntax errors
    has_exception::Bool             # exception is raised
    exception::term_t               # raised exception
    variables::term_t               # report variables
    varnames::term_t                # Report variables+names
    singles::term_t                 # Report singleton variables
    subtpos::term_t                 # Report Subterm positions
    comments::term_t                # Report comments
    cycles::Bool                    # Re-establish cycles
    dotlists::Bool                  # read .(a,b) as a list
    unicode_atoms::Sunicode_atoms_t # per-stream/per-call atom-content policy
    strictness::Int                 # Strictness level
    _rb::read_buffer                # keep read characters here
    vt::var_table                   # Data about variables
    ld::PL_local_data{T}
end


# ── the read buffer (pl-read.c) ─────────────────────────────────────────────────────────────────

# PORT: pl-read.c clearBuffer
# DIVERGES: the first buffer is zeroed, where upstream's `fast` array holds whatever the stack held:
# a syntax error raised before anything was read (`end_of_file_in_block_comment` at the start)
# reports the buffer's first byte as its text, which upstream reads uninitialised (swipl 10.1.16:
# `"\x1\"`, or the previous read's first character); here it is empty. Upstream report #8, drafted for the user to file.
"Empty the read buffer (pl-read.c)."
function clearBuffer(rd::read_data)::Nothing
    rb = rd._rb
    if rb.size == 0
        rb.base = zeros(UInt8, FASTBUFFERSIZE)
        rb.size = FASTBUFFERSIZE
    end
    rb.end_ = 1 + rb.size
    rd.base = rb.here = 1
    rd.posp = rd.base
    rd.posi = 0
    return nothing
end

# PORT: pl-read.c growToBuffer
"Double the read buffer and add byte `c` (pl-read.c)."
function growToBuffer(c::Int, rd::read_data)::Nothing
    rb = rd._rb
    resize!(rb.base, rb.size * 2)
    rd.posp = rd.base = 1
    rb.here = 1 + rb.size
    rb.size *= 2
    rb.end_ = 1 + rb.size
    rd.posi = 0
    rb.base[rb.here] = c % UInt8
    rb.here += 1
    return nothing
end

# PORT: pl-read.c addByteToBuffer
"Add byte `c` to the read buffer (pl-read.c)."
@inline function addByteToBuffer(c::Int, rd::read_data)::Nothing
    c &= 0xff
    rb = rd._rb
    if rb.here >= rb.end_
        growToBuffer(c, rd)
    else
        rb.base[rb.here] = c % UInt8
        rb.here += 1
    end
    return nothing
end

# PORT: pl-read.c addToBuffer
"Add character `c` to the read buffer, UTF-8 encoded (pl-read.c)."
function addToBuffer(c::Int, rd::read_data)::Nothing
    if c <= 0x7f
        addByteToBuffer(c, rd)
    else
        buf = UInt8[]
        utf8_put_char(buf, c)
        for b in buf
            addByteToBuffer(Int(b), rd)
        end
    end
    return nothing
end

# PORT: pl-read.c setCurrentSourceLocation
# DIVERGES: the file is the stream's when it is a named file stream (no stream table:
# `fileNameStream` is the IO's name); NOT PORTED: `LD->read_source`.
"Record where the term starts: the stream's position less the character just read (pl-read.c)."
function setCurrentSourceLocation(rd::read_data{T})::Nothing where {T}
    s = rd._rb.stream
    rd.start_of_term.file = nothing
    p = s.position
    sp = rd.start_of_term.position
    if p !== nothing
        sp.lineno = p.lineno
        sp.linepos = p.linepos - 1
        sp.charno = p.charno - 1
        # byteno maintained get getchr__()
    else
        sp.lineno = -1
        sp.linepos = -1
        sp.charno = 0
        sp.byteno = 0
    end
    return nothing
end

# PORT: pl-read.c getchr__
# DIVERGES: no character conversion table.
"The next character of the stream, its byte position recorded (pl-read.c `getchr`)."
function getchr__(rd::read_data)::Int
    s = rd._rb.stream
    p = s.position
    p !== nothing && (rd.start_of_term.position.byteno = p.byteno)
    return Sgetcode(s)
end

# PORT: pl-read.c getchrq
"The next character of the stream, as is (pl-read.c)."
getchrq(rd::read_data)::Int = Sgetcode(rd._rb.stream)

# PORT: pl-read.c setErrorLocation
# DIVERGES: no `LD->read_source`; the position is the error's, which `rawSyntaxError` reads.
"Move the error's location to `pos`, and the buffer back to its start (pl-read.c)."
function setErrorLocation(pos::Union{Nothing, IOPOS}, rd::read_data)::Nothing
    rd._rb.here = 2                                 # see rawSyntaxError()
    return nothing
end

# PORT: pl-read.c rawSyntaxError1
"A syntax error while reading the raw text: the buffer closed, the error at its end (pl-read.c)."
function rawSyntaxError1(what::String, arg::Union{Nothing, String}, rd::read_data)::Bool
    addToBuffer(0, rd)                              # EOS
    rd.base = 1
    rd.token_start = rd._rb.here - 1
    return errorWarningA1(what, arg, nothing, rd)
end

# PORT: pl-read.c rawSyntaxError
"A syntax error while reading the raw text (pl-read.c)."
rawSyntaxError(what::String, rd::read_data)::Bool = rawSyntaxError1(what, nothing, rd)

# PORT: pl-read.c raw_read_quoted
"""
Read quoted text that opens with `open` (already read) up to `close`, into the buffer as written:
the quotes, and escapes passed through for `get_token` (pl-read.c). False on an error.
"""
function raw_read_quoted(open::Int, close::Int, rd::read_data)::Bool
    s = rd._rb.stream
    p = s.position
    pos = if p !== nothing
        IOPOS(p.byteno, p.charno - 1, p.lineno, p.linepos - 1, p.esc_state)
    else
        nothing
    end
    addToBuffer(open, rd)
    c = getchrq(rd)
    eofinstr = false
    while c != EOF && c != close
        if c == Int('\\') && (rd.flags & M_CHARESCAPE) != 0
            addToBuffer(c, rd)
            c = getchrq(rd)
            if c == EOF
                eofinstr = true
                break
            elseif c == Int('u') || c == Int('U')   # \uXXXX, \UXXXXXXXX
                addToBuffer(c, rd)
                c = getchrq(rd)
                continue
            elseif c == Int('x')                    # \xNN\
                addToBuffer(c, rd)
                c = getchrq(rd)
                if c == EOF
                    eofinstr = true
                    break
                end
                if digitValue(16, c) >= 0
                    addToBuffer(c, rd)
                    c = getchrq(rd)
                    while digitValue(16, c) >= 0
                        addToBuffer(c, rd)
                        c = getchrq(rd)
                    end
                end
                if c == EOF
                    eofinstr = true
                    break
                end
                addToBuffer(c, rd)
                c == close && return true
                c = getchrq(rd)
                continue
            elseif c == Int('c')                    # \c<whitespace>*
                addToBuffer(c, rd)
                c = getchrq(rd)
                while PlBlankW(c)
                    addToBuffer(c, rd)
                    c = getchrq(rd)
                end
                (c == EOF || c == close) && break
                continue                            # goto next
            else
                addToBuffer(c, rd)
                if digitValue(8, c) >= 0            # \NNN\
                    c = getchrq(rd)
                    while digitValue(8, c) >= 0
                        addToBuffer(c, rd)
                        c = getchrq(rd)
                    end
                    if c == EOF
                        eofinstr = true
                        break
                    end
                    addToBuffer(c, rd)
                    c == close && return true
                    c = getchrq(rd)
                    continue
                elseif is_eol_char(c)               # \<newline>
                    c = getchrq(rd)
                    if c == EOF
                        eofinstr = true
                        break
                    end
                    addToBuffer(c, rd)
                    c == close && return true
                end
                c = getchrq(rd)
                continue                            # \symbolic-control-char
            end
        end
        addToBuffer(c, rd)
        c = getchrq(rd)
    end
    if c == EOF || eofinstr
        Sferror(s) != 0 && return false
        setErrorLocation(pos, rd)
        what = UInt8[]
        utf8_put_char(what, open)
        return rawSyntaxError1("end_of_file_in_quoted", String(what), rd)
    end
    addToBuffer(c, rd)
    return true
end

# PORT: pl-read.c raw_read_identifier
"Add the identifier starting with `c` to the buffer: the character after it (pl-read.c)."
function raw_read_identifier(c::Int, rd::read_data)::Int
    while true
        addToBuffer(c, rd)
        c = getchr__(rd)
        (c != EOF && PlIdContW(c)) || break
    end
    return c
end

# PORT: pl-read.c isStringStream
"Is `s` a string stream (pl-read.c)?"
isStringStream(s::IOSTREAM)::Bool = s.functions == Sstringfunctions

# PORT: pl-read.c backSkipUTF8
# DIVERGES: returns `(index, chr)`, where upstream writes `*chr`.
"The character ending just before index `e` of `b`, not before `start`: its index and code (pl-read.c)."
function backSkipUTF8(b::AbstractVector{UInt8}, start::Int, e::Int)::Tuple{Int, Int}
    s = e - 1
    while s > start && ISUTF8_CB(_byte(b, s))
        s -= 1
    end
    _, chr = utf8_get_char(b, s)
    return (s, chr)
end

# PORT: pl-read.c prev_code
"The code point that ends just before index `s` of the buffer, not before `start` (pl-read.c)."
prev_code(b::AbstractVector{UInt8}, start::Int, s::Int)::Int = backSkipUTF8(b, start, s)[2]

# PORT: pl-read.c backSkipBlanks
"The index after the last non-layout character before index `e`, not before `start` (pl-read.c)."
function backSkipBlanks(b::AbstractVector{UInt8}, start::Int, e::Int)::Int
    while e > start
        s = e - 1
        while s > start && ISUTF8_CB(_byte(b, s))
            s -= 1
        end
        e2, chr = utf8_get_char(b, s)
        @assert e2 == e
        PlBlankW(chr) || return e
        e = s
    end
    return start
end

# The C library's atoi on the digits at `i` of `b` (pl-read.c reads a radix this way).
function _atoi(b::AbstractVector{UInt8}, i::Int)::Int
    v = 0
    while isDigit(_byte(b, i))
        v = v * 10 + (_byte(b, i) - Int('0'))
        i += 1
    end
    return v
end

# PORT: pl-read.c set_start_line
# DIVERGES: a function of the flag it reads and returns, where upstream's macro assigns the local.
"At the term's first character, record where it starts (pl-read.c): the new `something_read`."
@inline function set_start_line(rd::read_data, something_read::Bool)::Bool
    something_read || setCurrentSourceLocation(rd)
    return true
end

# PORT: pl-read.c ensure_space
"Inside a term, add layout `c` unless the text already ends in a blank (pl-read.c)."
@inline function ensure_space(c::Int, rd::read_data, something_read::Bool)::Nothing
    if something_read && (is_eol_char(c) || !isBlank(Int(rd._rb.base[rd._rb.here - 1])))
        addToBuffer(c, rd)
    end
    return nothing
end

# PORT: pl-read.c raw_read2
# DIVERGES: no `comments(C)` read option (`_PL_rd->comments`: refused, NOT PORTED until a step
# needs it); reading past the end of a stream that raises it (`Sfpasteof`) is refused: its error
# names the stream, and there is no stream table; no quasi-quotations (SWI-7's default, refused by
# the parser, R1d).
"""
Read the text of one term from the stream into the buffer (pl-read.c): layout and comments
dropped (inside the term replaced by blanks, so positions stay right), quoted items kept as written,
up to the full stop. At end of file before a term the text is `end_of_file. `. False on an error.
"""
function raw_read2(rd::read_data)::Bool
    something_read = false
    clearBuffer(rd)                                 # clear input buffer
    rd.strictness = 0                               # truePrologFlag(PLFLAG_ISO): off
    s = rd._rb.stream
    c = getchr__(rd)
    while true
        # handle_c:
        if c == EOF
            Sferror(s) != 0 && return false
            Sfpasteof(s) == 1 &&
                throw(
                    NotPortedError{Nothing}(
                        nothing,
                        "raw_read2: reading past the end of a stream (its error names the stream)",
                        "the stream table (R2)"
                    )
                )
            if something_read
                if isStringStream(s)
                    ensure_space(Int(' '), rd, something_read)
                    addToBuffer(Int('.'), rd)
                    ensure_space(Int(' '), rd, something_read)
                    addToBuffer(0, rd)
                    return true
                end
                return rawSyntaxError("end_of_file", rd)
            elseif (rd.flags & M_RDSTRING_TERM) != 0
                return rawSyntaxError("end_of_string", rd)
            else
                something_read = set_start_line(rd, something_read)
                rb = rd._rb
                txt = codeunits("end_of_file. ")
                @assert rb.size >= length(txt) + 1      # clearBuffer: FASTBUFFERSIZE at least
                copyto!(rb.base, 1, txt, 1, length(txt))
                rb.here = 1 + 14
                rb.base[14] = 0x00                  # strcpy's terminator
                return true
            end
        elseif c == Int('/')
            p = s.position
            pos = if p !== nothing
                IOPOS(p.byteno, p.charno - 1, p.lineno, p.linepos - 1, 0)
            else
                nothing
            end
            c = getchr__(rd)
            if c == Int('*')
                rd.comments != 0 &&
                    throw(
                        NotPortedError{Nothing}(
                            nothing,
                            "raw_read2: the comments(C) read option",
                            "read_term options beyond R1d's"
                        )
                    )
                last = getchr__(rd)
                if last == EOF
                    setErrorLocation(pos, rd)
                    Sferror(s) != 0 && return false
                    return rawSyntaxError("end_of_file_in_block_comment", rd)
                end
                if something_read
                    addToBuffer(Int(' '), rd)       # positions
                    addToBuffer(Int(' '), rd)
                    addToBuffer(is_eol_char(last) ? last : Int(' '), rd)
                end
                level = 1
                while true
                    c = getchr__(rd)
                    is_bidi_override(c) && return bidi_override_error(c, rd)
                    if c == EOF
                        setErrorLocation(pos, rd)
                        Sferror(s) != 0 && return false
                        return rawSyntaxError("end_of_file_in_block_comment", rd)
                    elseif c == Int('*')
                        last == Int('/') && (level += 1)
                    elseif c == Int('/')
                        if last == Int('*')
                            level -= 1
                            if level == 0 || rd.strictness != 0
                                break
                            end
                        end
                    end
                    something_read && addToBuffer(is_eol_char(c) ? c : Int(' '), rd)
                    last = c
                end
                c = Int(' ')
                continue                            # goto handle_c
            else
                something_read = set_start_line(rd, something_read)
                addToBuffer(Int('/'), rd)
                if isSymbolW(c)
                    while c != EOF && isSymbolW(c) &&
                          !(c == Int('`') && (rd.flags & BQ_MASK) != 0)
                        addToBuffer(c, rd)
                        c = getchr__(rd)
                    end
                end
                continue                            # goto handle_c
            end
        elseif c == Int('%')
            something_read && addToBuffer(Int(' '), rd)
            rd.comments != 0 &&
                throw(
                    NotPortedError{Nothing}(
                        nothing,
                        "raw_read2: the comments(C) read option",
                        "read_term options beyond R1d's"
                    )
                )
            c = getchr__(rd)
            while c != EOF && !is_eol_char(c)
                is_bidi_override(c) && return bidi_override_error(c, rd)
                something_read && addToBuffer(Int(' '), rd)     # record positions
                c = getchr__(rd)
            end
            continue                                # goto handle_c: is the newline
        elseif c == Int('\'')
            rb = rd._rb
            sqatom = true
            if rb.here > 1 && isDigit(Int(rb.base[rb.here - 1]))
                bs = rb.here - 1
                bs > 1 && isDigit(Int(rb.base[bs - 1])) && (bs -= 1)
                if bs == 1 || !PlIdContW(prev_code(rb.base, 1, bs))
                    addToBuffer(0, rd)              # temp add trailing 0.
                    rb.here -= 1
                    base = _atoi(rb.base, bs)
                    if base <= 36
                        if base == 0                # 0'<c>
                            addToBuffer(c, rd)
                            c = getchr__(rd)
                            c == EOF && return rawSyntaxError("end_of_file", rd)
                            addToBuffer(c, rd)
                            if c == Int('\\')       # 0'\<c>
                                c = getchr__(rd)
                                c != EOF && addToBuffer(c, rd)
                            elseif c == Int('\'')   # 0''
                                c = getchr__(rd)
                                if c != EOF
                                    if c == Int('\'')
                                        addToBuffer(c, rd)
                                    else
                                        continue    # goto handle_c
                                    end
                                end
                            end
                            sqatom = false          # break
                        else
                            c2 = Speekcode(s)
                            c2 == EOF && return rawSyntaxError("end_of_file", rd)
                            if digitValue(base, c2) >= 0
                                addToBuffer(c, rd)
                                c = Sgetcode(s)
                                addToBuffer(c, rd)
                                sqatom = false      # break
                            end
                        end
                    end
                end
            end
            if sqatom
                something_read = set_start_line(rd, something_read)
                raw_read_quoted(c, c, rd) || return false
            end
        elseif c == Int('"')
            something_read = set_start_line(rd, something_read)
            raw_read_quoted(c, c, rd) || return false
        elseif c == Int('.')
            addToBuffer(c, rd)
            something_read = set_start_line(rd, something_read)
            c = Speekcode(s)
            if isBlankW(c) || c == Int('%') || c == -1
                rd._rb.here - 1 == 1 && return rawSyntaxError("end_of_clause", rd)
                addToBuffer(Int(' '), rd)
                addToBuffer(0, rd)
                return true
            end
            c = getchr__(rd)
            if PlSymbolW(c)
                while c != EOF && PlSymbolW(c) &&
                      !(c == Int('`') && (rd.flags & BQ_MASK) != 0)
                    addToBuffer(c, rd)
                    c = getchr__(rd)
                end
            end
            continue                                # goto handle_c
        elseif c == Int('`') && (rd.flags & BQ_MASK) != 0
            something_read = set_start_line(rd, something_read)
            raw_read_quoted(c, c, rd) || return false
        elseif (c % UInt32) < 0x80
            t = CharTypeA(c)
            if t == SP
                # blank:
                while true
                    if something_read       # positions, \0 --> ' '
                        addToBuffer(c != 0 ? c : Int(' '), rd)
                    else
                        ensure_space(c, rd, something_read)
                    end
                    c = getchr__(rd)
                    (c != EOF && PlBlankW(c)) || break
                end
                continue                            # goto handle_c
            elseif t == SY
                # symbol:
                something_read = set_start_line(rd, something_read)
                while true
                    addToBuffer(c, rd)
                    c = getchr__(rd)
                    c == Int('`') && (rd.flags & BQ_MASK) != 0 && break
                    (c != EOF && PlSymbolW(c)) || break
                end
                continue                            # goto handle_c
            elseif t == LC || t == UC
                something_read = set_start_line(rd, something_read)
                c = raw_read_identifier(c, rd)
                continue                            # goto handle_c
            else
                addToBuffer(c, rd)
                something_read = set_start_line(rd, something_read)
            end
        else                                        # >= 0x80
            close_cp, is_open = pl_pair_lookup(c)
            if close_cp != 0 && is_open && U_CAT_OF(uflagsRaw(c)) == U_CAT_QUOTE
                something_read = set_start_line(rd, something_read)
                raw_read_quoted(c, close_cp, rd) || return false
            elseif PlIdStartW(c)
                something_read = set_start_line(rd, something_read)
                c = raw_read_identifier(c, rd)
                continue                            # goto handle_c
            elseif PlBlankW(c)
                while true                          # goto blank
                    if something_read
                        addToBuffer(c != 0 ? c : Int(' '), rd)
                    else
                        ensure_space(c, rd, something_read)
                    end
                    c = getchr__(rd)
                    (c != EOF && PlBlankW(c)) || break
                end
                continue
            elseif PlSymbolW(c)
                something_read = set_start_line(rd, something_read)                    # goto symbol (unreachable: ASCII only)
                while true
                    addToBuffer(c, rd)
                    c = getchr__(rd)
                    c == Int('`') && (rd.flags & BQ_MASK) != 0 && break
                    (c != EOF && PlSymbolW(c)) || break
                end
                continue
            else
                addToBuffer(c, rd)
                something_read = set_start_line(rd, something_read)
            end
        end
        c = getchr__(rd)                            # for(;;) { c = getchr(); …
    end
end

# PORT: pl-read.c raw_read
# DIVERGES: no terminal handling (`PushTty`: no ttys); returns `(ok, end)`, where upstream writes
# `*endp`.
"Read the raw text of one term (pl-read.c): `(ok, end)`, `end` the buffer index after it."
function raw_read(rd::read_data)::Tuple{Bool, Int}
    rc = raw_read2(rd)
    return (rc, rd._rb.here)
end

# ── syntax errors (pl-read.c) ───────────────────────────────────────────────────────────────────
# error(syntax_error(Id), file(Path, Line, LinePos, CharNo))   reading a file
# error(syntax_error(Id), string(String, CharNo))              reading a string
# error(syntax_error(Id), stream(Stream, Line, LinePos, CharNo))   NOT PORTED: no stream table

# PORT: pl-read.c str_number_error
"The syntax error's name for a number's status (pl-read.c)."
function str_number_error(rc::strnumstat)::String
    rc == NUM_ERROR && return "illegal_number"
    rc == NUM_OK && return "no_error"
    rc == NUM_FUNDERFLOW && return "float_underflow"
    rc == NUM_FOVERFLOW && return "float_overflow"
    rc == NUM_IOVERFLOW && return "integer_overflow"
    return "numeric constant out of range"
end

# PORT: pl-read.c ptr_to_location
# DIVERGES: returns the location, where upstream writes `*pos`.
"The source location of buffer index `here`: the term's start, moved over the text before it."
function ptr_to_location(here::Int, rd::read_data{T})::source_location{T} where {T}
    st = rd.start_of_term
    p = st.position
    pos = source_location{T}(st.file, IOPOS(p.byteno, p.charno, p.lineno, p.linepos, 0))
    b = rd._rb.base
    ll = 0
    s = rd.base
    while true                                      # update line number
        s, c = utf8_get_char(b, s)
        s < here || break
        pos.position.charno += 1
        if is_eol_char(c)
            pos.position.lineno += 1
            ll = s + 1
        end
    end
    if ll != 0                                      # update line position
        s = ll
        pos.position.linepos = 0
    else
        s = rd.base
    end
    while s < here
        ch = _byte(b, s)
        if ch == Int('\b')
            pos.position.linepos > 0 && (pos.position.linepos -= 1)
        elseif ch == Int('\t')
            pos.position.linepos |= 7               # TBD: set tab distance
            pos.position.linepos += 1
        else
            pos.position.linepos += 1
        end
        s += 1
    end
    pos.position.byteno = 0                         # we do not know
    return pos
end

# The read text from the buffer's base to its first 0 byte, as a String.
function _rd_text(rd::read_data)::String
    b = rd._rb.base
    e = rd.base
    while e <= length(b) && b[e] != 0x00
        e += 1
    end
    return String(b[rd.base:(e - 1)])
end

# PORT: pl-read.c unify_location
# DIVERGES: builds the location term, where upstream unifies a term reference with it; a stream
# that is neither a file nor a string is NOT PORTED (its location names the stream).
"The location term of `pos`: `file(…)`, or `string(Text, CharNo)` for a string stream (pl-read.c)."
function unify_location(pos::source_location{T}, rd::read_data{T})::T where {T}
    f = pos.file
    if f !== nothing                                # reading a file
        return mk_expr(
            T,
            T[mk_sym(T, :file), f, mk_gnd(T, Int(pos.position.lineno)),
                mk_gnd(T, Int(pos.position.linepos)), mk_gnd(T, Int(pos.position.charno))]
        )
    elseif isStringStream(rd._rb.stream)
        charno = pos.position.charno - rd.start_of_term.position.charno
        return mk_expr(
            T, T[mk_sym(T, :string), mk_gnd(T, _rd_text(rd)), mk_gnd(T, Int(charno))]
        )
    end
    throw(
        NotPortedError{Nothing}(
            nothing,
            "unify_location: a stream's location, stream(S, L, LP, C)",
            "the stream table (R2)"
        )
    )
end

# PORT: pl-read.c makeErrorTerm
# DIVERGES: returns the term, where upstream returns a term reference to it.
"`error(syntax_error(Id), Location)`, the location the last token's start (pl-read.c)."
function makeErrorTerm(
    id_str::String, id_arg::Union{Nothing, String}, id_term::Union{Nothing, T},
    rd::read_data{T}
)::T where {T}
    if id_term === nothing
        id_term = if id_arg !== nothing
            mk_expr(T, T[mk_sym(T, Symbol(id_str)), mk_sym(T, Symbol(id_arg))])
        else
            mk_sym(T, Symbol(id_str))
        end
    end
    loc = unify_location(ptr_to_location(rd.token_start, rd), rd)
    return mk_expr(
        T, T[mk_sym(T, :error), mk_expr(T, T[mk_sym(T, :syntax_error), id_term]), loc]
    )
end

# PORT: pl-read.c errorWarningA1
# DIVERGES: the read data holds the error (`has_exception`, its `exception` slot), as upstream's
# does when it has read data; `id_term` is a term (`nothing` for upstream's 0).
"Record a syntax error in the read data; false, always (pl-read.c)."
function errorWarningA1(
    id_str::String, id_arg::Union{Nothing, String}, id_term::Union{Nothing, T},
    rd::read_data{T}
)::Bool where {T}
    Sferror(rd._rb.stream) != 0 && return false     # Stream error; reported elsewhere
    ld = rd.ld
    ld.exception_processing = true                  # allow using spare stack
    ex = makeErrorTerm(id_str, id_arg, id_term, rd)
    rd.has_exception = true
    ld.slots[rd.exception + 1] = ex
    return false
end

# PORT: pl-read.c errorWarning
"Record a syntax error in the read data; false, always (pl-read.c)."
errorWarning(id_str::String, id_term::Union{Nothing, T}, rd::read_data{T}) where {T} =
    errorWarningA1(id_str, nothing, id_term, rd)

# PORT: pl-read.c numberError
"Record the syntax error of a number's status (pl-read.c)."
numberError(rc::strnumstat, rd::read_data{T}) where {T} =
    errorWarning(str_number_error(rc), nothing, rd)

# PORT: pl-read.c bidi_override_error
"Record `syntax_error(bidi_override(C))` (pl-read.c)."
bidi_override_error(c::Int, rd::read_data{T}) where {T} =
    errorWarning("", mk_expr(T, T[mk_sym(T, :bidi_override), mk_gnd(T, c)]), rd)

# PORT: pl-read.c check_no_bidi_override
"True if the bytes from `start` to `e` hold no bidi override; else the syntax error (pl-read.c)."
function check_no_bidi_override(start::Int, e::Int, rd::read_data{T})::Bool where {T}
    b = rd._rb.base
    p = start
    while p < e
        p, c = utf8_get_char(b, p)
        is_bidi_override(c) && return bidi_override_error(c, rd)
    end
    return true
end

# PORT: pl-read.c syntaxError
"Record syntax error `what`; false, always (pl-read.c)."
syntaxError(what::String, rd::read_data{T}) where {T} = errorWarning(what, nothing, rd)

# ── skipping (pl-read.c) ────────────────────────────────────────────────────────────────────────

# PORT: pl-read.c utf8_skip_blanks
"The index of the first non-layout character from `inp` (pl-read.c)."
function utf8_skip_blanks(b::AbstractVector{UInt8}, inp::Int)::Int
    while _byte(b, inp) != 0
        s, chr = utf8_get_char(b, inp)
        PlBlankW(chr) || return inp
        inp = s
    end
    return inp
end

# PORT: pl-read.c skipSpaces
"The index of the first non-layout character from `inp` (pl-read.c)."
skipSpaces(b::AbstractVector{UInt8}, inp::Int)::Int = utf8_skip_blanks(b, inp)

# PORT: pl-read.c SkipVarIdCont
"The index after the identifier characters from `inp` (pl-read.c)."
function SkipVarIdCont(b::AbstractVector{UInt8}, inp::Int)::Int
    while _byte(b, inp) != 0
        s, chr = utf8_get_char(b, inp)
        PlIdContW(chr) || return inp
        inp = s
    end
    return inp
end

# PORT: pl-read.c SkipAtomIdCont
# DIVERGES: the `dot_in_atom` flag is off (SWI-7's default), as there are no Prolog flags yet.
"The index after the identifier characters of an atom from `inp` (pl-read.c)."
function SkipAtomIdCont(b::AbstractVector{UInt8}, inp::Int)::Int
    while _byte(b, inp) != 0
        s, chr = utf8_get_char(b, inp)
        PlIdContW(chr) || return inp                 # (no dot_in_atom)
        inp = s
    end
    return inp
end

# PORT: pl-read.c SkipSymbol
"The index after the symbol characters from `inp` (pl-read.c)."
function SkipSymbol(b::AbstractVector{UInt8}, inp::Int, rd::read_data)::Int
    while _byte(b, inp) != 0
        s, chr = utf8_get_char(b, inp)
        if chr == Int('`') && (rd.flags & BQ_MASK) == 0
            inp = s                                  # ` is a symbol char
            continue
        end
        PlSymbolW(chr) || return inp
        if chr == rd.var_prefix                     # <symbol>?var
            _, c2 = utf8_get_char(b, s)
            PlIdContW(c2) && return inp
        end
        inp = s
    end
    return inp
end

# ── escapes and quoted text (pl-read.c) ─────────────────────────────────────────────────────────

# PORT: pl-read.c ESC_EOS
"`escape_char`: no more data (pl-read.c)."
const ESC_EOS = -1
# PORT: pl-read.c ESC_ERROR
"`escape_char`: an error (pl-read.c)."
const ESC_ERROR = -2

# PORT: pl-read.c escape_char
# DIVERGES: returns `(chr, end)`, where upstream writes `*end`; `rd` is `nothing` for upstream's
# NULL (a `0'\c` character, not quoted text).
"""
Decode the escape after a backslash at index `inp` of `b` (pl-read.c): `(chr, end)`, `chr` the code,
`ESC_EOS` if there is no more data, `ESC_ERROR` on an error (recorded inp `rd`).
"""
function escape_char(
    b::AbstractVector{UInt8}, inp::Int, quote_::Int, rd::Union{Nothing, read_data}
)::Tuple{Int, Int}
    while true                                      # again:
        inp, c = utf8_get_char(b, inp)
        if c == Int('a')
            return (7, inp)                          # 7 is ASCII BELL
        elseif c == Int('b')
            return (Int('\b'), inp)
        elseif c == Int('c')                        # skip \c<blank>*
            if rd !== nothing
                inp = skipSpaces(b, inp)
                e, c = utf8_get_char(b, inp)
                inp = e                              # skip_cont:
                c == Int('\\') && continue          # goto again
                c == quote_ && return (ESC_EOS, inp)  # \c ' --> no output
                return (c, inp)
            end
            return (Int('c'), inp)
        elseif c == Int('\r') || c == 0x0085 || c == 0x2028 || c == 0x2029 || c == Int('\n')
            if c == Int('\r')                       # \\\r\n is the same as \\\n
                in2, c2 = utf8_get_char(b, inp)
                c2 == Int('\n') && (c=c2; inp=in2)
            end
            if rd !== nothing                       # quoted string, _not_ 0'\..
                if rd.strictness == 0
                    # DIVERGES: the `swi_backslash_newline` warning for skipped layout is not
                    # printed (no message system); the text read is upstream's.
                    e = inp
                    while _byte(b, inp) != 0
                        e, c = utf8_get_char(b, inp)
                        (is_eol_char(c) || !PlBlankW(c)) && break
                        inp = e
                    end
                else
                    e, c = utf8_get_char(b, inp)
                end
                inp = e                              # skip_cont:
                c == Int('\\') && continue          # goto again
                c == quote_ && return (ESC_EOS, inp)
                return (c, inp)
            end
            return (Int('\n'), inp)
        elseif c == Int('e')
            return (27, inp)                         # 27 is ESC (\e is a gcc extension)
        elseif c == Int('f')
            return (Int('\f'), inp)
        elseif c == Int('\\') || c == Int('\'') || c == Int('"') || c == Int('`')
            return (c, inp)
        elseif c == Int('n')
            return (Int('\n'), inp)
        elseif c == Int('r')
            return (Int('\r'), inp)
        elseif c == Int('t')
            return (Int('\t'), inp)
        elseif c == Int('s')                        # \s is space (NU-Prolog, Quintus)
            return (Int(' '), inp)
        elseif c == Int('v')
            return (11, inp)                         # 11 is ASCII Vertical Tab
        elseif c == Int('u') || c == Int('U')       # \uXXXX, \UXXXXXXXX
            digits = c == Int('u') ? 4 : 8
            errpos = inp - 1
            chr = 0
            while digits > 0
                digits -= 1
                c = _byte(b, inp)
                inp += 1
                dv = digitValue(16, c)
                if dv >= 0
                    chr = (chr << 4) + dv
                else
                    if rd !== nothing
                        rd.token_start = errpos
                        errorWarning("Illegal \\u or \\U sequence", nothing, rd)
                    end
                    return (ESC_ERROR, inp)
                end
            end
            if !VALID_CODE_POINT(chr)
                if rd !== nothing
                    rd.token_start = errpos
                    errorWarning("Illegal character code", nothing, rd)
                end
                return (ESC_ERROR, inp)
            end
            return (chr, inp)
        else
            base = 0
            if c == Int('x')
                c = _byte(b, inp)
                inp += 1
                if digitValue(16, c) >= 0
                    base = 16                       # goto numchar
                else
                    inp -= 2
                    c = _byte(b, inp)
                    inp += 1                         # goto undef
                end
            elseif c >= Int('0') && c <= Int('7')   # octal number
                base = 8
            end
            if base != 0                            # numchar:
                errpos = inp - 1
                chr = digitValue(base, c)
                c = _byte(b, inp)
                inp += 1
                dv = digitValue(base, c)
                while dv >= 0
                    chr = chr * base + dv
                    c = _byte(b, inp)
                    inp += 1
                    if !VALID_CODE_POINT(chr)
                        if rd !== nothing
                            rd.token_start = errpos
                            errorWarning("Illegal character code", nothing, rd)
                        end
                        return (ESC_ERROR, inp)
                    end
                    dv = digitValue(base, c)
                end
                c != Int('\\') && (inp -= 1)
                return (chr, inp)
            elseif c == quote_
                return (c, inp)
            end
            # undef:
            if rd !== nothing
                rd.token_start = inp - 1
                errorWarningA1("undefined_char_escape", string(Char(c)), nothing, rd)
            end
            return (ESC_ERROR, inp)
        end
    end
end

# PORT: pl-read.c addUTF8Buffer
"Append character `c` to `b`, UTF-8 encoded (pl-read.c)."
addUTF8Buffer(b::Vector{UInt8}, c::Int)::Nothing = utf8_put_char(b, c)

# PORT: pl-read.c get_string
# DIVERGES: returns `(ok, end)`, where upstream writes `*end`.
"""
The text of the quoted item at index `inp` of the read buffer into `buf`, its quote doubled or
escaped, its escapes decoded, up to `ein` (pl-read.c): `(ok, end)`; the error is recorded inp `rd`.
"""
function get_string(inp::Int, ein::Int, buf::Vector{UInt8}, rd::read_data)::Tuple{Bool, Int}
    b = rd._rb.base
    quote_ = _byte(b, inp)
    inp += 1
    c = _byte(b, inp)
    inp += 1
    while true
        # next:
        if c == quote_
            if _byte(b, inp) == quote_
                inp += 1
            else
                break
            end
        elseif c == Int('\\') && (rd.flags & M_CHARESCAPE) != 0
            c, inp = escape_char(b, inp, quote_, rd)
            if c >= 0
                addUTF8Buffer(buf, c)
                c = _byte(b, inp)
                inp += 1
                continue
            elseif c == ESC_ERROR
                return (false, inp)
            else
                break
            end
        elseif c >= 0x80                            # copy UTF-8 sequence
            _, code = utf8_get_char(b, inp - 1)
            is_bidi_override(code) && return (bidi_override_error(code, rd), inp)
            while true
                push!(buf, c % UInt8)
                c = _byte(b, inp)
                inp += 1
                c > 0x80 || break
            end
            continue                                # goto next
        elseif inp > ein
            errorWarning("end_of_file_in_string", nothing, rd)
            return (false, inp)
        end
        push!(buf, c % UInt8)
        c = _byte(b, inp)
        inp += 1
    end
    return (true, inp)
end

# PORT: pl-read.c get_unicode_quoted_string
# DIVERGES: returns `(ok, end)`, where upstream writes `*end`.
"""
The text of a Unicode-quoted item from index `inp` (after its opening quote) up to `close`, into
`buf`, escapes decoded, no doubling of the close (pl-read.c): `(ok, end)`.
"""
function get_unicode_quoted_string(
    inp::Int, close::Int, ein::Int, buf::Vector{UInt8}, rd::read_data
)::Tuple{Bool, Int}
    b = rd._rb.base
    while true
        if inp >= ein
            errorWarning("end_of_file_in_string", nothing, rd)
            return (false, inp)
        end
        inp, c = utf8_get_char(b, inp)
        c == close && break
        if c == Int('\\') && (rd.flags & M_CHARESCAPE) != 0
            c, inp = escape_char(b, inp, 0, rd)
            if c >= 0
                addUTF8Buffer(buf, c)
                continue
            elseif c == ESC_ERROR
                return (false, inp)
            else
                break
            end
        end
        is_bidi_override(c) && return (bidi_override_error(c, rd), inp)
        addUTF8Buffer(buf, c)
    end
    return (true, inp)
end

# PORT: pl-read.c read_unicode_quote_token
"""
The token of a Unicode-quoted item opened by `open` (pl-read.c): `'<open><close>'(Value)`, its
value the text as `double_quotes` makes it, a `TK_STRING`. False on an error.
"""
function read_unicode_quote_token(open::Int, close::Int, rd::read_data{T})::Bool where {T}
    buf = UInt8[]
    ok, e = get_unicode_quoted_string(rd.here, close, rd.end_, buf, rd)
    ok || return false
    rd.here = e
    type = if (rd.flags & DBLQ_STRING) != 0
        :string
    elseif (rd.flags & DBLQ_ATOM) != 0
        :atom
    elseif (rd.flags & DBLQ_CHARS) != 0
        :chars
    else
        :codes
    end
    str = _text_term(T, buf, type)
    fb = UInt8[]
    utf8_put_char(fb, open)
    utf8_put_char(fb, close)
    tok = rd.token
    tok.term_value = mk_expr(T, T[_atom_from_text(T, String(fb)), str])
    tok.type = TK_STRING
    return true
end

# ── numbers (pl-read.c: scan_decimal, scan_number, str_number and the float helpers) ────────────
# A `cucharp` is a position in a byte buffer: these functions take the buffer and a 1-based index
# and return the moved index beside their result, where upstream moves a pointer through
# `cucharp *`. The buffer reads 0 past its end (`_byte`), as upstream's are 0-terminated.

# PORT: pl-read.c skip_digit_separator
"Skip a digit separator before a digit of `base` at `s`: `(true, next)`, or `(false, s)` (pl-read.c)."
function skip_digit_separator(b::AbstractVector{UInt8}, s::Int, base::Int)::Tuple{Bool, Int}
    p = s
    if _byte(b, p) == Int('_')
        p = skipSpaces(b, p + 1)
    elseif _byte(b, p) == Int(' ') && base <= 10
        p += 1
    end
    digitValue(base, _byte(b, p)) >= 0 && return (true, p)
    return (false, s)
end

# PORT: pl-read.c skip_decimal_separator
"Skip a digit separator before a decimal digit from `zero`: `(true, next)`, or `(false, s)` (pl-read.c)."
function skip_decimal_separator(
    b::AbstractVector{UInt8}, s::Int, zero::Int
)::Tuple{Bool, Int}
    p = s
    if _byte(b, p) == Int('_')
        p = skipSpaces(b, p + 1)
    elseif _byte(b, p) == Int(' ')
        p += 1
    end
    _, c = utf8_get_char(b, p)
    isDecimal(zero, c) && return (true, p)
    return (false, s)
end

# PORT: pl-read.c scan_decimal
# DIVERGES: returns `(status, next, grouped)`, where upstream moves `*sp` and writes `*grouped`.
"""
Scan the decimal digits from `zero` at `s` into `n`, an integer (a big one past 64 bits),
negative if `negative`: `(status, next, grouped)`, `grouped` if a digit separator was skipped.
"""
function scan_decimal(
    b::AbstractVector{UInt8}, s::Int, zero::Int, negative::Bool, n::number
)::Tuple{strnumstat, Int, Bool}
    maxi = typemax(Int64) ÷ 10
    maxlastdigit = typemax(Int64) % 10
    mini = typemin(Int64) ÷ 10
    minlastdigit = typemin(Int64) % 10
    t = Int64(0)
    grouped = false
    sn, c = utf8_get_char(b, s)
    isDecimal(zero, c) || return (NUM_ERROR, s, grouped)
    while true
        sn, c = utf8_get_char(b, s)
        while isDecimal(zero, c)
            if (negative && ((t < mini) || (t == mini && zero - c < minlastdigit))) ||
                (!negative && ((t > maxi) || (t == maxi && c - zero > maxlastdigit)))
                n.i = t
                n.type = V_INTEGER
                promoteToMPZNumber(n)
                while true
                    sn, c = utf8_get_char(b, s)
                    while isDecimal(zero, c)
                        s = sn
                        n.mpz = n.mpz * 10 + (negative ? -(c - zero) : (c - zero))
                        sn, c = utf8_get_char(b, s)
                    end
                    ok, s2 = skip_decimal_separator(b, s, zero)
                    ok || break
                    s = s2
                    grouped = true
                end
                return (NUM_OK, s, grouped)
            else
                s = sn
                t = negative ? t * 10 - (c - zero) : t * 10 + (c - zero)
            end
            sn, c = utf8_get_char(b, s)
        end
        ok, s2 = skip_decimal_separator(b, s, zero)
        ok || break
        s = s2
        grouped = true
    end
    n.i = t
    n.type = V_INTEGER
    return (NUM_OK, s, grouped)
end

# PORT: pl-read.c scan_number
# DIVERGES: returns `(status, next)`, where upstream moves `*s`.
"Scan the digits of base `base` at `q` into `n`, negative if `negative`: `(status, next)` (pl-read.c)."
function scan_number(
    bf::AbstractVector{UInt8}, q::Int, negative::Bool, b::Int, n::number
)::Tuple{strnumstat, Int}
    maxi = typemax(Int64) ÷ b
    maxlastdigit = Int(typemax(Int64) % b)
    mini = typemin(Int64) ÷ b
    minlastdigit = Int(typemin(Int64) % b)
    t = Int64(0)
    digitValue(b, _byte(bf, q)) < 0 && return (NUM_ERROR, q)    # syntax error
    while true
        d = digitValue(b, _byte(bf, q))
        while d >= 0
            if (negative && ((t < mini) || (t == mini && d > minlastdigit))) ||
                (!negative && ((t > maxi) || (t == maxi && d > maxlastdigit)))
                n.i = t
                n.type = V_INTEGER
                promoteToMPZNumber(n)
                while true
                    d = digitValue(b, _byte(bf, q))
                    while d >= 0
                        q += 1
                        n.mpz = n.mpz * b + (negative ? -d : d)
                        d = digitValue(b, _byte(bf, q))
                    end
                    ok, q2 = skip_digit_separator(bf, q, b)
                    ok || break
                    q = q2
                end
                return (NUM_OK, q)
            else
                q += 1
                t = negative ? t * b - d : t * b + d
            end
            d = digitValue(b, _byte(bf, q))
        end
        ok, q2 = skip_digit_separator(bf, q, b)
        ok || break
        q = q2
    end
    n.i = t
    n.type = V_INTEGER
    return (NUM_OK, q)
end

# PORT: pl-read.c float_tag
"The index after `tag` if the text at `inp` is `tag` not followed by an identifier character, else 0."
function float_tag(b::AbstractVector{UInt8}, inp::Int, tag::String)::Int
    t = codeunits(tag)
    k = 1
    while _byte(b, inp) != 0 && k <= length(t) && _byte(b, inp) == Int(t[k])
        inp += 1
        k += 1
    end
    if k > length(t)
        if _byte(b, inp) != 0
            _, c = utf8_get_char(b, inp)
            PlIdContW(c) && return 0
        end
        return inp
    end
    return 0
end

# PORT: pl-read.c starts_1dot
"Does the text at `s` start with `1.` or `-1.` (pl-read.c)?"
function starts_1dot(b::AbstractVector{UInt8}, s::Int)::Bool
    _byte(b, s) == Int('-') && (s += 1)
    return _byte(b, s) == Int('1') && _byte(b, s + 1) == Int('.')
end

# PORT: pl-read.c points_at_decimal
"Is the character at `inp` a digit from `zero` (pl-read.c)?"
function points_at_decimal(b::AbstractVector{UInt8}, inp::Int, zero::Int)::Bool
    _, c = utf8_get_char(b, inp)
    return isDecimal(zero, c)
end

# PORT: pl-read.c skip_decimals
"The index after the digits from `zero` at `inp` (pl-read.c)."
function skip_decimals(b::AbstractVector{UInt8}, inp::Int, zero::Int)::Int
    n, c = utf8_get_char(b, inp)
    while isDecimal(zero, c)
        inp = n
        n, c = utf8_get_char(b, inp)
    end
    return inp
end

# PORT: pl-read.c special_float
# DIVERGES: returns `(status, next)`, where upstream moves `*in`.
"Read `Inf` or `NaN` after a float's digits at `inp`, the float starting at `start` (pl-read.c)."
function special_float(
    b::AbstractVector{UInt8}, inp::Int, start::Int, value::number
)::Tuple{strnumstat, Int}
    s = float_tag(b, inp, "Inf")
    if s != 0
        value.f = _byte(b, start) == Int('-') ? -Inf : Inf
    else
        s = float_tag(b, inp, "NaN")
        if s != 0 && starts_1dot(b, start)
            f, e, _ = _strtod(b, start)
            if e == inp
                rc, f = make_nan(f)
                rc != NUM_OK && return (rc, inp)
                value.f = f
            else
                return (NUM_CONSTRANGE, inp)
            end
        else
            return (NUM_ERROR, inp)
        end
    end
    return (NUM_OK, s)
end

# The C library's strtod on the text at index `s` of `b`: `(value, end index, errno)`. The text is
# copied with a 0 terminator (strtod reads up to one).
function _strtod(b::AbstractVector{UInt8}, s::Int)::Tuple{Float64, Int, Int}
    n = s
    while _byte(b, n) != 0
        n += 1
    end
    tmp = Vector{UInt8}(undef, n - s + 1)
    for k in s:(n - 1)
        tmp[k - s + 1] = b[k]
    end
    tmp[end] = 0x00
    endp = Ref{Ptr{UInt8}}(C_NULL)
    GC.@preserve tmp begin
        p = pointer(tmp)
        Libc.errno(0)
        d = ccall(:strtod, Cdouble, (Ptr{UInt8}, Ptr{Ptr{UInt8}}), p, endp)
        err = Libc.errno()
        return (d, s + Int(endp[] - p), err)
    end
end

# PORT: pl-read.c ascii_to_double
# DIVERGES: returns `(status, value)`, where upstream writes `*dp`; the float flags are `ld`'s.
"The float the ASCII text from `s` to `e` writes, through the C library's strtod (pl-read.c)."
function ascii_to_double(
    ld::PL_local_data{T}, b::AbstractVector{UInt8}, s::Int, e::Int
)::Tuple{strnumstat, Float64} where {T}
    d, es, err = _strtod(b, s)
    if es == e || (_byte(b, e) == Int('.') && e + 1 == es)
        if err == Libc.ERANGE
            if abs(d) > 1.0
                (ld.arith_f_flags & FLT_OVERFLOW) == 0 && return (NUM_FOVERFLOW, d)
            else
                (ld.arith_f_flags & FLT_UNDERFLOW) == 0 && return (NUM_FOVERFLOW, d)
            end
        end
        return (NUM_OK, d)
    end
    return (NUM_ERROR, d)
end

# PORT: pl-read.c to_double
# DIVERGES: returns `(status, value)`, where upstream writes `*dp`.
"The float the text from `s` to `e` writes, its digits from `zero` (pl-read.c)."
function to_double(
    ld::PL_local_data{T}, b::AbstractVector{UInt8}, s::Int, e::Int, zero::Int
)::Tuple{strnumstat, Float64} where {T}
    zero == Int('0') && return ascii_to_double(ld, b, s, e)
    buf = UInt8[]
    while s < e
        s, c = utf8_get_char(b, s)
        if c >= zero
            @assert c <= zero + 9
            push!(buf, UInt8(c - zero + Int('0')))
        else
            @assert c <= 127
            push!(buf, UInt8(c))
        end
    end
    push!(buf, 0x00)
    return ascii_to_double(ld, buf, 1, length(buf))
end

# PORT: pl-read.c str_number
# DIVERGES: returns `(status, end)`, where upstream writes `*end`; `ld` for the float flags.
"""
Read the number at index `inp` of `b` into `value` (pl-read.c): integers in every base syntax
(`0'c`, `0x…`, `0o…`, `0b…`, `N'digits`), digit groups, rationals (`1r3`; `1/3` with `RAT_NATURAL`
inp `flags`), floats with `Inf` and `NaN`. Returns the status and the index after the number.
"""
function str_number(
    ld::PL_local_data{T}, b::AbstractVector{UInt8}, inp::Int, value::number, flags::UInt32
)::Tuple{strnumstat, Int} where {T}
    negative = false
    start = inp
    if _byte(b, inp) == Int('-')                     # skip optional sign
        negative = true
        inp += 1
    elseif _byte(b, inp) == Int('+')
        inp += 1
    end
    if _byte(b, inp) == Int('0')
        base = 0
        c1 = _byte(b, inp + 1)
        if c1 == Int('\'')                          # 0'<char>
            if (flags & M_CHARESCAPE) != 0 && _byte(b, inp + 2) == Int('\\')   # 0'\n, etc
                chr, e = escape_char(b, inp + 3, Int('\''), nothing)
                chr < 0 && return (NUM_ERROR, inp)
            else
                e, chr = utf8_get_char(b, inp + 2)
                if chr == Int('\'') && _byte(b, e) == Int('\'')   # handle 0''' as 0''
                    e += 1
                end
            end
            value.i = Int64(chr)
            negative && (value.i = -value.i)        # -0'a is a bit dubious!
            value.type = V_INTEGER
            return (NUM_OK, e)
        elseif c1 == Int('b')
            base = 2
        elseif c1 == Int('x')
            base = 16
        elseif c1 == Int('o')
            base = 8
        end
        if base != 0                                # 0b<binary>, 0x<hex>, 0o<oct>
            inp += 2
            rc, inp = scan_number(b, inp, negative, base, value)
            rc != NUM_OK && return (rc, inp)
            return (NUM_OK, inp)
        end
    end
    zero = Int('0')
    _, c0 = utf8_get_char(b, inp)
    PlDecimalW(c0) && (zero = c0 - decimal_weight(c0))
    rc, inp, grouped = scan_decimal(b, inp, zero, negative, value)
    rc != NUM_OK && return (rc, inp)                 # too large?
    if (
        (_byte(b, inp) == Int('/') && (flags & RAT_NATURAL) != 0) ||
        _byte(b, inp) == Int('r')
    ) &&
        points_at_decimal(b, inp + 1, zero)
        num = number()
        den = number()
        inp += 1
        rc, inp, grouped = scan_decimal(b, inp, zero, false, den)
        if rc != NUM_OK
            clearNumber(value)
            return (rc, inp)                         # too large?
        end
        if den.type == V_INTEGER && den.i == 0
            clearNumber(value)                      # n/0
            return (NUM_ERROR, inp)
        end
        cpNumber(num, value)
        promoteToMPZNumber(num)
        promoteToMPZNumber(den)
        clearNumber(value)
        ar_rdiv_mpz(num, den, value)
        return (NUM_OK, inp)
    end
    grouped && return (NUM_OK, inp)
    # base'value number
    if _byte(b, inp) == Int('\'') && zero == Int('0') && value.type == V_INTEGER
        base = value.i
        base < 0 && (base = -base)
        if base <= 36 && base > 1 && digitValue(Int(base), _byte(b, inp + 1)) >= 0
            inp += 1
            rc, inp = scan_number(b, inp, negative, Int(base), value)
            rc == NUM_ERROR && return (rc, inp)      # number too large (upstream: !rc)
            return (NUM_OK, inp)
        end
    end
    # floating point numbers
    if _byte(b, inp) == Int('.') && points_at_decimal(b, inp + 1, zero)
        clearNumber(value)
        value.type = V_FLOAT
        inp = skip_decimals(b, inp + 1, zero)
        rc, s = special_float(b, inp, start, value)
        if rc != NUM_ERROR
            return (rc, rc == NUM_OK ? s : inp)
        end
    end
    c = _byte(b, inp)
    if (c == Int('e') || c == Int('E')) &&
        (
        (isSign(_byte(b, inp + 1)) && points_at_decimal(b, inp + 2, zero)) ||
        points_at_decimal(b, inp + 1, zero)
    )
        clearNumber(value)
        value.type = V_FLOAT
        inp += 1
        isSign(_byte(b, inp)) && (inp += 1)
        inp = skip_decimals(b, inp, zero)
    end
    if value.type == V_FLOAT
        rc, f = to_double(ld, b, start, inp, zero)
        rc != NUM_OK && return (rc, inp)
        value.f = f
        return (NUM_OK, inp)
    end
    return (NUM_OK, inp)
end

# ── the variable table's functions (pl-read.c) ──────────────────────────────────────────────────

# PORT: pl-read.c VAR_INDEX_HASH_OFFSET
"A bucket holds a variable's index plus this; 0 is the empty bucket (pl-read.c)."
const VAR_INDEX_HASH_OFFSET = 1

# PORT: pl-read.c isVarPrefixSymbol
"Can `c` prefix an anonymous variable's name, as inp `?_` (pl-read.c)?"
isVarPrefixSymbol(c::Int)::Bool = isSymbol(c)

# PORT: pl-read.c isAnonVarNameN
"Is the `len`-byte name at `n` an anonymous variable's: `_`, or a prefix symbol and `_`?"
function isAnonVarNameN(b::AbstractVector{UInt8}, n::Int, len::Int)::Bool
    return (len == 1 && _byte(b, n) == Int('_')) ||
           (len == 2 && _byte(b, n + 1) == Int('_') && isVarPrefixSymbol(_byte(b, n)))
end

# PORT: pl-read.c variableHash
"The hash of a variable's name (pl-read.c)."
variableHash(var::variable)::UInt32 = MurmurHashAligned2(var.name, var.namelen, MURMUR_SEED)

# PORT: pl-read.c linkVariable
"Put `var` in its hash bucket (pl-read.c)."
function linkVariable(var::variable, rd::read_data)::Nothing
    vt = rd.vt
    key = Int(variableHash(var) % UInt32(vt.var_hash_size))
    var.hash_next = vt.var_buckets[key + 1]
    vt.var_buckets[key + 1] = var.signature + VAR_INDEX_HASH_OFFSET
    return nothing
end

# PORT: pl-read.c rehashVariables
"Start the hash table at 32 buckets, or double it, and put every variable in it (pl-read.c)."
function rehashVariables(rd::read_data)::Int
    vt = rd.vt
    vt.var_hash_size = vt.var_hash_size == 0 ? 32 : vt.var_hash_size * 2
    vt.var_buckets = zeros(Int, vt.var_hash_size)
    for v in vt.var_buffer
        linkVariable(v, rd)
    end
    return 0
end

# PORT: pl-read.c hashVariable
"Put a new variable in the hash table, growing it when the variables outnumber its buckets."
function hashVariable(var::variable, rd::read_data)::Int
    i = var.signature
    i > rd.vt.var_hash_size && return rehashVariables(rd)
    linkVariable(var, rd)
    return 0
end

# PORT: pl-read.c var_from_index
"The variable with index `i` (pl-read.c)."
var_from_index(i::Int, rd::read_data)::variable = rd.vt.var_buffer[i + 1]

# PORT: pl-read.c lookupVariable
# DIVERGES: returns the variable's index, where upstream returns a pointer to its record.
"""
The variable named by the `len` bytes at index `name` of the read buffer (pl-read.c): the one
already met, its count incremented, or a new one; `_` is always new.
"""
function lookupVariable(name::Int, len::Int, rd::read_data)::Int
    b = rd._rb.base
    vt = rd.vt
    if !isAnonVarNameN(b, name, len)                # always add _
        if vt.var_hash_size != 0
            key = Int(
                MurmurHashAligned2(view(b, name:(name + len - 1)), len, MURMUR_SEED) %
                UInt32(vt.var_hash_size)
            )
            vi = vt.var_buckets[key + 1]
            while vi != 0
                var = var_from_index(vi - VAR_INDEX_HASH_OFFSET, rd)
                if len == var.namelen && _same_bytes(b, name, var.name, len)
                    var.times += 1
                    return var.signature
                end
                vi = var.hash_next
            end
        else
            for v in vt.var_buffer
                if len == v.namelen && _same_bytes(b, name, v.name, len)
                    v.times += 1
                    return v.signature
                end
            end
        end
    end
    nv = length(vt.var_buffer)
    var = variable(b[name:(name + len - 1)], len, 0, 1, 0, nv, false)
    push!(vt.var_buffer, var)
    nv >= 16 && hashVariable(var, rd)
    return nv
end

# Are the `len` bytes at index `i` of `b` those of `name` (upstream's strncmp)?
function _same_bytes(b::AbstractVector{UInt8}, i::Int, name::Vector{UInt8}, len::Int)::Bool
    for k in 1:len
        _byte(b, i + k - 1) == Int(name[k]) || return false
    end
    return true
end


# ── the tokeniser (pl-read.c) ───────────────────────────────────────────────────────────────────

# The atom whose text is `str` (upstream's `textToAtom`). An atom is a Julia `Symbol` in the term
# interface, which cannot hold the character 0; upstream's atoms can (`'a\0\b'` reads as
# `[97,0,98]` in swipl 10.1.16): refused explicitly here, never misread.
function _atom_from_text(::Type{T}, str::String)::T where {T}
    occursin('\0', str) && throw(
        NotPortedError{Nothing}(
            nothing, "an atom containing the character 0 (a Symbol cannot hold it)",
            "the term interface"
        )
    )
    return mk_sym(T, Symbol(str))
end

# The atom whose text is the `len` UTF-8 bytes at index `s` of `b` (upstream's `textToAtom`).
_text_atom(::Type{T}, b::AbstractVector{UInt8}, s::Int, len::Int) where {T} =
    _atom_from_text(T, String(b[s:(s + len - 1)]))

# The text `bytes` (UTF-8) as the term `PL_unify_text` makes of it for `type`: a string, an atom,
# a list of codes or a list of one-character atoms.
function _text_term(::Type{T}, bytes::Vector{UInt8}, type::Symbol)::T where {T}
    str = String(copy(bytes))
    type === :string && return mk_gnd(T, str)
    type === :atom && return _atom_from_text(T, str)
    l = mk_nil(T)
    for ch in reverse(collect(str))
        e = type === :codes ? mk_gnd(T, Int(ch)) : _atom_from_text(T, string(ch))
        l = mk_expr(T, T[mk_sym(T, Symbol("[|]")), e, l])
    end
    return l
end

# PORT: pl-read.c ptr_to_pos
"The character position of buffer index `p`, counted from the term's start (pl-read.c)."
function ptr_to_pos(p::Int, rd::read_data)::Int
    b = rd._rb.base
    i = rd.posi
    s = rd.posp
    while s < p
        s = utf8_skip_char(b, s)
        i += 1
    end
    rd.posp = p
    rd.posi = i
    return i
end

# PORT: pl-read.c backskip_utf8
"The index of the character that ends just before index `s` (pl-read.c)."
function backskip_utf8(b::AbstractVector{UInt8}, s::Int)::Int
    s -= 1
    while ISUTF8_CB(_byte(b, s))
        s -= 1
    end
    return s
end

# PORT: pl-read.c get_token
# DIVERGES: a string token's value is the term (`term_value`), where upstream holds a term
# reference; a variable token's is the variable's index. NOT PORTED: blobs (`<type>(…)`, SWI-7
# reads them only with the `blobs` read option), the `charset` style check, NFC and non-ASCII atom
# policies other than accept (S_UATOMS_ACCEPT, SWI-7's default); quasi-quotations (TK_QQ_OPEN,
# TK_QQ_BAR: off by default).
"""
The next token of the raw text (pl-read.c), or `nothing` after a syntax error (recorded inp `rd`).
`must_be_op`: an operator is expected here, so `-` before a digit is not a sign.
"""
function get_token(must_be_op::Bool, rd::read_data{T})::Union{Nothing, token{T}} where {T}
    tok = rd.token
    if rd._unget
        rd._unget = false
        return tok
    end
    b = rd._rb.base
    rd.here = skipSpaces(b, rd.here)
    start = rd.token_start = rd.here
    tok.start = rd.start_of_term.position.charno + ptr_to_pos(rd.token_start, rd)
    rd.here, c = utf8_get_char(b, rd.here)
    if is_bidi_override(c)
        bidi_override_error(c, rd)
        return nothing
    end
    cls = -1                                        # the ASCII case to take
    if c >= 0x80
        cat = PlCatW(c)
        if cat == U_CAT_ID_START_VARIABLE
            cls = UC                                # goto upper
        elseif cat == U_CAT_ID_START_ATOM
            cls = LC                                # goto lower
        elseif cat == U_CAT_BRACKET
            close, is_open = pl_pair_lookup(c)
            if close != 0 && is_open                # '<open><close>' atom, like {}
                e = skipSpaces(b, rd.here)
                e2, c2 = utf8_get_char(b, e)
                if c2 == close
                    rd.here = e2                    # consume the close
                    buf = UInt8[]
                    utf8_put_char(buf, c)
                    utf8_put_char(buf, close)
                    tok.atom = _atom_from_text(T, String(buf))
                    tok.type = _byte(b, rd.here) == Int('(') ? TK_FUNCTOR : TK_NAME
                    @goto out
                end
            end
            tok.character = c
            tok.type = TK_PUNCTUATION
            @goto out
        elseif cat == U_CAT_QUOTE
            mate, is_open = pl_pair_lookup(c)
            if mate != 0 && is_open
                read_unicode_quote_token(c, mate, rd) || return nothing
                @goto out
            end
            tok.character = c                       # Stray quote close at top level
            tok.type = TK_PUNCTUATION
            @goto out
        elseif cat == U_CAT_SOLO || cat == U_CAT_ID_CONTINUE_SOLO ||
            cat == U_CAT_PATTERN_SYNTAX
            cls = SO                                # goto case_solo
        else
            syntaxError("illegal_character", rd)
            return nothing
        end
    else
        cls = CharTypeA(c)
    end

    if cls == UC && rd.var_prefix != 0 && c != rd.var_prefix
        cls = LC                                    # goto lower
    end
    if cls == LC                                    # lower:
        rd.here = SkipAtomIdCont(b, rd.here)
        check_no_bidi_override(start, rd.here, rd) || return nothing
        @goto functor
    elseif cls == UC                                # upper: variable:
        @label variable
        rd.here = SkipVarIdCont(b, rd.here)
        check_no_bidi_override(start, rd.here, rd) || return nothing
        # (no allow_variable_name_as_functor: off by default)
        if isAnonVarNameN(b, start, rd.here - start) && rd.variables == 0     # report them
            tok.type = _byte(b, rd.here) == Int('{') ? TK_VOID_DICT : TK_VOID
        else
            tok.variable = lookupVariable(start, rd.here - start, rd)
            tok.type = _byte(b, rd.here) == Int('{') ? TK_VCLASS_DICT : TK_VARIABLE
        end
        @goto out
    elseif cls == DI                                # case_digit:
        @label case_digit
        rc, e = str_number(rd.ld, b, backskip_utf8(b, rd.here), tok.number, rd.flags)
        rd.here = e
        if rc == NUM_OK
            tok.type = TK_NUMBER
            @goto out
        end
        numberError(rc, rd)
        return nothing
    elseif cls == SO                                # case_solo:
        tok.atom = mk_sym(T, Symbol(string(Char(c))))   # codeToAtom(c)
        tok.type = _byte(b, rd.here) == Int('(') ? TK_FUNCTOR : TK_NAME
        @goto out
    elseif cls == SY || (cls == BQ && (rd.flags & BQ_MASK) == 0)    # case_symbol:
        if c == rd.var_prefix                       # e.g., ?var
            _, c2 = utf8_get_char(b, rd.here)
            PlIdContW(c2) && @goto variable
        end
        # (no blobs: `<type>(…)` is read only with the blobs option)
        rd.here = SkipSymbol(b, rd.here, rd)
        check_no_bidi_override(start, rd.here, rd) || return nothing
        if rd.here == start + 1
            if c == Int('-') && !must_be_op && isDigit(_byte(b, rd.here))    # -number
                @goto case_digit
            end
            if c == Int('.') && _byte(b, rd.here) != 0
                _, c2 = utf8_get_char(b, rd.here)
                if PlBlankW(c2)                     # .<blank>
                    tok.type = TK_FULLSTOP
                    @goto out
                end
            end
        end
        @goto functor                               # goto symbol
    elseif cls == PU
        if c == Int('{') || c == Int('[')
            rd.here = skipSpaces(b, rd.here)
            if _byte(b, rd.here) == matchingBracket(c)
                rd.here += 1
                tok.atom = c == Int('{') ? mk_sym(T, Symbol("{}")) : mk_nil(T)
                tok.type = _byte(b, rd.here) == Int('(') ? TK_FUNCTOR : TK_NAME
                @goto out
            end
        end
        tok.character = c
        tok.type = TK_PUNCTUATION
        @goto out
    elseif cls == SQ
        buf = UInt8[]
        ok, e = get_string(rd.here - 1, rd.end_, buf, rd)
        ok || return nothing
        rd.here = e
        tok.atom = _atom_from_text(T, String(buf))
        nx = _byte(b, rd.here)
        tok.type = if nx == Int('(')
            TK_FUNCTOR
        elseif nx == Int('{')
            TK_DICT
        else
            TK_QNAME
        end
        @goto out
    elseif cls == DQ
        buf = UInt8[]
        ok, e = get_string(rd.here - 1, rd.end_, buf, rd)
        ok || return nothing
        rd.here = e
        type = if (rd.flags & DBLQ_STRING) != 0
            :string
        elseif (rd.flags & DBLQ_ATOM) != 0
            :atom
        elseif (rd.flags & DBLQ_CHARS) != 0
            :chars
        else
            :codes
        end
        tok.term_value = _text_term(T, buf, type)
        tok.type = TK_STRING
        @goto out
    elseif cls == BQ                                # case_bq: (BQ_MASK set)
        type = if (rd.flags & BQ_STRING) != 0
            :string
        elseif (rd.flags & BQ_CODES) != 0
            :codes
        else
            :chars
        end
        buf = UInt8[]
        ok, e = get_string(rd.here - 1, rd.end_, buf, rd)
        ok || return nothing
        rd.here = e
        tok.term_value = _text_term(T, buf, type)
        tok.type = TK_STRING
        @goto out
    elseif cls == CT
        syntaxError("illegal_character", rd)
        return nothing
    end
    error("read/1: tokeniser internal error")       # sysError

    @label functor                                  # symbol: functor: (lower)
    tok.atom = _text_atom(T, b, start, rd.here - start)
    nx = _byte(b, rd.here)
    tok.type = if nx == Int('(')
        TK_FUNCTOR
    elseif nx == Int('{')
        TK_DICT
    else
        TK_NAME
    end

    @label out
    tok.end_ = rd.start_of_term.position.charno + ptr_to_pos(rd.here, rd)
    return tok
end

# PORT: pl-read.c init_read_data
# DIVERGES: returns the read data, where upstream initialises a caller's struct; the module is
# `MODULE_parse` (`user`: no source is being loaded until R1f); `styleCheck` 0 (no style checks
# until the loader); no character conversion table.
"Fresh read data for reading from stream `inp` (pl-read.c)."
function init_read_data(
    gd::PL_global_data{T}, ld::PL_local_data{T}, inp::IOSTREAM
)::read_data{T} where {T}
    m = MODULE_user(gd)                             # MODULE_parse
    rd = read_data{T}(
        0, 0, 0, 0, token{T}(), false, RD_MAGIC,
        source_location{T}(nothing, IOPOS()), 0, 0,
        m.index, m.flags, 0, 0,                     # module, its syntax flags, var_prefix, style
        :error, false, PL_new_term_ref(ld),         # on_error, has_exception, exception
        0, 0, 0, 0, 0,                              # variables, varnames, singles, subtpos, comments
        false, false, inp.unicode_atoms, 0,          # cycles, dotlists, unicode_atoms, strictness
        read_buffer(0, UInt8[], 0, 0, inp), var_table(), ld
    )
    return rd
end
