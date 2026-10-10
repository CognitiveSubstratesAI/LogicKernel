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
# the tokeniser (`get_token`). Since R1d the PARSER: the term stack, the operator queues and their
# resolution, `complex_term`'s state machine (its suspended levels on a vector of frames), the
# list, bracket and compound readers, `read_term`; and `atom_to_term/3`, `term_to_atom/2`,
# `term_string/2` — since R1e's core, in both directions (the write: src/pl-write.jl
# `PL_write_term`). read_term/2,3 take a stream (the stream table, R2).

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

# PORT: pl-read.c f_is_prolog_var_start
"Can `c` start a variable (pl-read.c)?"
f_is_prolog_var_start(c::Int)::Bool = PlUpperW(c) || c == Int('_')

# PORT: pl-read.c f_is_prolog_atom_start
"Can `c` start an unquoted atom (pl-read.c)?"
f_is_prolog_atom_start(c::Int)::Bool = PlIdStartW(c) && !(PlUpperW(c) || c == Int('_'))

# PORT: pl-read.c f_is_prolog_identifier_continue
"Can `c` continue an identifier (pl-read.c)?"
f_is_prolog_identifier_continue(c::Int)::Bool = PlIdContW(c) || c == Int('_')

# PORT: pl-read.c f_is_prolog_symbol
"Is `c` a symbol character (pl-read.c)?"
f_is_prolog_symbol(c::Int)::Bool = PlSymbolW(c)

# PORT: pl-read.c f_is_prolog_solo
"Is `c` a solo character (pl-read.c)?"
f_is_prolog_solo(c::Int)::Bool = PlSoloW(c)

# PORT: pl-read.c f_is_pattern_syntax
"Is `c` in Unicode's Pattern_Syntax set (pl-read.c)?"
f_is_pattern_syntax(c::Int)::Bool = PlCatW(c) == U_CAT_PATTERN_SYNTAX

# PORT: pl-read.c f_paren_close
"The bracket that closes the opening bracket `chr`, else -1 (pl-read.c)."
function f_paren_close(chr::Int)::Int
    if PlCatW(chr) == U_CAT_BRACKET
        close, is_open = pl_pair_lookup(chr)
        close != 0 && is_open && return close
    end
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

# PORT: pl-read.c term_stack
# DIVERGES: the terms themselves, where upstream keeps term references whose cells hold them: a
# term is an immutable value here. Upstream's read VARIABLE is a word naming its record
# (`varInfo`), which only `readValHandle` turns into a variable; `vars` says what each entry is —
# `TS_VALUE` a plain value, `TS_UNBOUND` an unbound cell (`setVar`), else a variable record's index.
"The terms the parser has read and not yet built into their parent (pl-read.c)."
mutable struct term_stack{T}
    terms::Vector{T}                # Term handles
    vars::Vector{Int}               # what each entry is (see above)
    allocated::Int                  # #valid terms allocated
    top::Int                        # #valid terms on the stack
end
term_stack{T}() where {T} = term_stack{T}(T[], Int[], 0, 0)

"A term-stack entry that holds a plain value (`term_stack.vars`)."
const TS_VALUE = -1
"A term-stack entry that holds an unbound cell (`term_stack.vars`): upstream's `setVar`."
const TS_UNBOUND = -2

# PORT: pl-read.c op_entry
# DIVERGES: the operator's name and its block are two fields, where upstream overlays them (`op`,
# a union `isterm` selects); the block is the term itself (as `term_stack`); copied
# (`copy_op_entry`) where upstream copies the struct; no term position (`tpos`: positions are
# refused, R1's decision); `token_start` is an index into the read buffer.
"An operator the parser met: its name or block, kind, type and priorities (pl-read.c)."
mutable struct op_entry{T}
    atom::Union{Nothing, T}         # op.atom: Normal operator
    block::Union{Nothing, T}        # op.block: [...] or {...} operator
    isblock::Bool                   # [...] or {...} operator
    isterm::Bool                    # Union is a term
    kind::Int                       # kind (OP_PREFIX, ...)
    type::UInt8                     # OP_FX, ...
    left_pri::Int                   # priority at left-hand
    right_pri::Int                  # priority at right hand
    op_pri::Int                     # priority of operator
    token_start::Int                # start of the token for message
end
op_entry{T}() where {T} = op_entry{T}(nothing, nothing, false, false, 0, 0x00, 0, 0, 0, 0)

# A copy of `e`: upstream copies the struct by value (`queue_side_op`, a frame's `in_op`).
copy_op_entry(e::op_entry{T}) where {T} = op_entry{T}(
    e.atom, e.block, e.isblock, e.isterm, e.kind, e.type, e.left_pri, e.right_pri,
    e.op_pri,
    e.token_start
)

# PORT: pl-read.c out_entry
# DIVERGES: no term position (`tpos`: positions are refused, R1's decision).
"An operand on the out queue (pl-read.c): its priority; the term itself is on the term stack."
struct out_entry
    pri::Int                        # priority of the term
end

# PORT: pl-read.c op_queues
"The parser's two queues, shared by every level of the term being read (pl-read.c)."
struct op_queues{T}
    out_queue::Vector{out_entry}    # Queued `out' terms
    side_queue::Vector{op_entry{T}} # Operators pushed `aside'
end
op_queues{T}() where {T} = op_queues{T}(out_entry[], op_entry{T}[])

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
# `gd` and `ld` are the database and the engine's local data, which upstream reaches through `GD`
# and `LD`. NOT PORTED: quasi-quotations (`quasi_quotations`, `qq`, `qq_tail`: a quasi-quotation
# is refused, R1's decision); blobs (`blobs`, `blob_start`: read only with the blob option); atom
# GC (`locked`); the character conversion table (`char_conversion/2`).
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
    term_stack::term_stack{T}       # Stack for creating output term
    op::op_queues{T}                # Operator handling
    gd::PL_global_data{T}
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
# DIVERGES: `LD->read_source` gets a copy (a struct assignment upstream).
"Record where the term starts: the stream's position less the character just read (pl-read.c)."
function setCurrentSourceLocation(rd::read_data{T})::Nothing where {T}
    s = rd._rb.stream
    rd.start_of_term.file = fileNameStream(rd.gd, s)   # NULL_ATOM: nothing
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
    ld = rd.ld                                      # LD->read_source = _PL_rd->start_of_term
    ld.read_source = source_location{T}(
        rd.start_of_term.file, IOPOS(sp.byteno, sp.charno, sp.lineno, sp.linepos, 0)
    )
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

# PORT: pl-read.c raw_read_quasi_quotation
"""
Read the raw text of a quasi-quotation's body (pl-read.c), from the second `|` of its `||` to the
`|}` that ends it, as written; false, with `end_of_file_in_quasi_quotation`, at the end of the text.
"""
function raw_read_quasi_quotation(c::Int, rd::read_data)::Bool
    addToBuffer(c, rd)
    while (c = getchrq(rd)) != EOF
        addToBuffer(c, rd)
        if c == Int('}') && rd._rb.base[rd._rb.here - 2] == UInt8('|')
            return true
        end
    end
    return rawSyntaxError("end_of_file_in_quasi_quotation", rd)
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
# names the stream, and there is no stream table. The `quasi_quotations` flag is ON (SWI-7's
# default, as swipl 10.1.16's), so `||` reads a quasi-quotation's raw text, which the parser then
# refuses (R1's decision).
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
                            elseif c == Int('|')    # 0'|| (O_QUASIQUOTATIONS)
                                c = getchr__(rd)
                                if c != EOF
                                    if c == Int('|')
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
            elseif c == Int('|') && rd._rb.here - 1 >= 1 &&
                rd._rb.base[rd._rb.here - 1] == UInt8('|')
                # detect || from {|Syntax||Quotation|}: truePrologFlag(PLFLAG_QUASI_QUOTES) is
                # on (SWI-7's default)
                raw_read_quasi_quotation(c, rd) || return false
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
# KNOWN UPSTREAM DEFECT, ported AS IS (docs/upstream_reports.md #10): the argument is made with
# `PL_CHARS`, whose text is ISO Latin-1, but `raw_read_quoted` passes the UTF-8 of the quote — so a
# non-ASCII quote's error names its BYTES: `«x` raises `end_of_file_in_quoted('Â«')` (probed).
"`error(syntax_error(Id), Location)`, the location the last token's start (pl-read.c)."
function makeErrorTerm(
    id_str::String, id_arg::Union{Nothing, String}, id_term::Union{Nothing, T},
    rd::read_data{T}
)::T where {T}
    if id_term === nothing
        id_term = if id_arg !== nothing
            latin1 = String(Char.(codeunits(id_arg)))       # PL_CHARS: ISO Latin-1 text
            mk_expr(T, T[mk_sym(T, Symbol(id_str)), mk_sym(T, Symbol(latin1))])
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
                # char tmp[2] = {(char)c, EOS}: the code point's LOW BYTE, read by
                # makeErrorTerm as ISO Latin-1 — a KNOWN UPSTREAM DEFECT ported as is
                # (docs/upstream_reports.md #10): `\Ω` names `©`, `\∀` the empty atom
                lowbyte = UInt8(c & 0xff)
                tmp = lowbyte == 0x00 ? "" : String(UInt8[lowbyte])
                errorWarningA1("undefined_char_escape", tmp, nothing, rd)
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
# policies other than accept (S_UATOMS_ACCEPT, SWI-7's default). The `quasi_quotations` flag is
# ON (SWI-7's default): `{|` is TK_QQ_OPEN and `||` TK_QQ_BAR.
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
        # (O_QUASIQUOTATIONS, truePrologFlag(PLFLAG_QUASI_QUOTES): on)
        if c == Int('{') && _byte(b, rd.here) == Int('|')
            rd.here += 1
            tok.type = TK_QQ_OPEN
            @goto out
        end
        if c == Int('{') || c == Int('[')           # FALLTHROUGH from '{'
            rd.here = skipSpaces(b, rd.here)
            if _byte(b, rd.here) == matchingBracket(c)
                rd.here += 1
                tok.atom = c == Int('{') ? mk_sym(T, Symbol("{}")) : mk_nil(T)
                tok.type = _byte(b, rd.here) == Int('(') ? TK_FUNCTOR : TK_NAME
                @goto out
            end
        end
        # case '|', reached from '{' and '[' too (upstream's fallthrough)
        if (c == Int('{') || c == Int('[') || c == Int('|')) &&
            _byte(b, rd.here) == Int('|')
            rd.here += 1
            tok.type = TK_QQ_BAR
            @goto out
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
# `MODULE_parse` — `user` (`read_clause` sets the source module: `set_module_read_data`); no
# character conversion table.
"Fresh read data for reading from stream `inp` (pl-read.c)."
function init_read_data(
    gd::PL_global_data{T}, ld::PL_local_data{T}, inp::IOSTREAM
)::read_data{T} where {T}
    m = MODULE_user(gd)                             # MODULE_parse
    rd = read_data{T}(
        0, 0, 0, 0, token{T}(), false, RD_MAGIC,
        source_location{T}(nothing, IOPOS()), 0, 0,
        m.index, m.flags, 0, ld.debugstatus_styleCheck,    # module, syntax flags, var_prefix, style
        :error, false, PL_new_term_ref(ld),         # on_error, has_exception, exception
        0, 0, 0, 0, 0,                              # variables, varnames, singles, subtpos, comments
        false, false, inp.unicode_atoms, 0,          # cycles, dotlists, unicode_atoms, strictness
        read_buffer(0, UInt8[], 0, 0, inp), var_table(), term_stack{T}(), op_queues{T}(),
        gd, ld
    )
    init_term_stack(rd)
    return rd
end


# ── the term stack (pl-read.c) ──────────────────────────────────────────────────────────────────

# PORT: pl-read.c init_term_stack
"Empty the term stack (pl-read.c)."
function init_term_stack(rd::read_data)::Nothing
    ts = rd.term_stack
    empty!(ts.terms)
    empty!(ts.vars)
    ts.allocated = 0
    ts.top = 0
    return nothing
end

# PORT: pl-read.c alloc_term
# DIVERGES: returns the new entry's index; it holds an unbound cell (`TS_UNBOUND`), where upstream
# returns a term reference reset to a variable (`PL_put_variable`) or a new one (see `term_stack`).
"A new entry on top of the term stack, an unbound cell (pl-read.c)."
function alloc_term(rd::read_data{T})::Int where {T}
    ts = rd.term_stack
    if ts.top < ts.allocated
        ts.top += 1
        ts.vars[ts.top] = TS_UNBOUND                # PL_put_variable(t)
    else
        push!(ts.terms, mk_nil(T))                  # t = PL_new_term_ref(): its value is unread
        push!(ts.vars, TS_UNBOUND)
        ts.allocated += 1
        ts.top = ts.allocated
    end
    return ts.top
end

# PORT: pl-read.c term_av
# DIVERGES: the index of entry `top + n` (`term_av(-1)`: the top entry), where upstream returns a
# pointer into the stack's term references.
"The index of the term-stack entry `n` from the top: `term_av(-2)` is the second from the top (pl-read.c)."
term_av(n::Int, rd::read_data)::Int = rd.term_stack.top + n + 1

# PORT: pl-read.c truncate_term_stack
# DIVERGES: `top` is an entry's index (`term_av`), where upstream passes a pointer to it.
"Drop the term stack's entries from index `top` up (pl-read.c)."
function truncate_term_stack(top::Int, rd::read_data)::Nothing
    rd.term_stack.top = top - 1
    return nothing
end

# PORT: pl-read.c setHandle as _setHandle!
# DIVERGES: the entry `h` of the term stack holds the plain value `w` (see `term_stack`).
"Make term-stack entry `h` hold the term `w` (pl-read.c)."
function _setHandle!(h::Int, w::T, rd::read_data{T})::Nothing where {T}
    ts = rd.term_stack
    ts.terms[h] = w
    ts.vars[h] = TS_VALUE
    return nothing
end

# The term the term-stack entry `h` holds, as upstream's `valTermRef` reads it: an unbound cell is
# a fresh variable; never a variable record's (those are read with `readValHandle`).
function _ts_term(h::Int, rd::read_data{T})::T where {T}
    ts = rd.term_stack
    ts.vars[h] == TS_VALUE && return ts.terms[h]
    @assert ts.vars[h] == TS_UNBOUND
    return mk_var(T, fresh_var_keys!(1))
end

# ── term building (pl-read.c) ───────────────────────────────────────────────────────────────────

# PORT: pl-read.c readValHandle
# DIVERGES: returns the term to place, where upstream writes it to `argp`. A variable record's
# FIRST placement makes its variable — a new term reference, whose fresh key IS the variable — so
# the variables are made in the order upstream gives them their cells, and the kernel's order of
# variables (`var_key`) is swipl's (by address); a later placement reuses it. An unbound cell is a
# fresh variable, as upstream's copied unbound word is a new variable in its new cell.
"The term to place for term-stack entry `term`, which is cleared (pl-read.c)."
function readValHandle(term::Int, rd::read_data{T})::T where {T}
    ts = rd.term_stack
    ld = rd.ld
    tag = ts.vars[term]
    w = if tag >= 0                                 # var = varInfo(w)
        var = var_from_index(tag, rd)
        if var.variable == 0                        # new variable
            var.variable = PL_new_term_ref(ld)
            @assert var.variable != 0
        end
        ld.slots[var.variable + 1]                  # (or) reference to existing var
    elseif tag == TS_UNBOUND
        mk_var(T, fresh_var_keys!(1))               # setVar(*argp)
    else
        ts.terms[term]                              # plain value
    end
    ts.vars[term] = TS_UNBOUND                      # setVar(*valTermRef(term))
    return w
end

# PORT: pl-read.c build_term
# DIVERGES: the compound is made by `mk_expr` over its name and its arguments (there is no global
# stack to run out of: `ensureGlobalSpace` and `ensureSpaceForTermRefs` cannot fail); `arity` 0 is
# SWI-7's `f()`, a compound with no arguments.
"Replace the top `arity` terms of the term stack by `atom` applied to them (pl-read.c)."
function build_term(atom::T, arity::Int, rd::read_data{T})::Bool where {T}
    if arity > 0
        argv = term_av(-arity, rd)
        kids = Vector{T}(undef, arity + 1)
        kids[1] = atom                              # *argp++ = functor
        for k in 0:(arity - 1)
            kids[k + 2] = readValHandle(argv + k, rd)
        end
        _setHandle!(argv, mk_expr(T, kids), rd)
        truncate_term_stack(argv + 1, rd)
    else
        t = alloc_term(rd)
        _setHandle!(t, mk_expr(T, T[atom]), rd)
    end
    return true
end

# The list `[e1, …, en | tail]` of `elements` (upstream builds it cell by cell, `FUNCTOR_dot2`).
function _read_list_term(elements::Vector{T}, tail::T)::T where {T}
    l = tail
    for k in length(elements):-1:1
        l = mk_expr(T, T[mk_sym(T, LIST_CONS_NAME), elements[k], l])
    end
    return l
end

# ── the operator queues (pl-read.c) ─────────────────────────────────────────────────────────────

# PORT: pl-read.c queue_side_op
# DIVERGES: a copy of `new` is pushed, as upstream copies the struct.
"Push the operator `new` on the side queue (pl-read.c)."
function queue_side_op(new::op_entry{T}, rd::read_data{T})::Nothing where {T}
    push!(rd.op.side_queue, copy_op_entry(new))
    return nothing
end

# PORT: pl-read.c side_op
"The side queue's entry `i`, counted from 0 (pl-read.c)."
side_op(i::Int, rd::read_data{T}) where {T} = rd.op.side_queue[i + 1]

# PORT: pl-read.c pop_side_op
"Pop the side queue's top entry (pl-read.c)."
function pop_side_op(rd::read_data)::Nothing
    pop!(rd.op.side_queue)
    return nothing
end

# PORT: pl-read.c side_p0
"The index of the side queue's top entry, counted from 0 (pl-read.c): -1 when it is empty."
side_p0(rd::read_data)::Int = length(rd.op.side_queue) - 1

# PORT: pl-read.c queue_out_op
# DIVERGES: no term position (`tpos`: positions are refused, R1's decision).
"Push an operand of priority `pri` on the out queue (pl-read.c)."
function queue_out_op(pri::Int, rd::read_data)::Nothing
    push!(rd.op.out_queue, out_entry(pri))
    return nothing
end

# PORT: pl-read.c out_op
# DIVERGES: the index of the entry `i` from the top (`out_op(-1)`: the top entry), where upstream
# returns a pointer.
"The index of the out queue's entry `i` from its top (pl-read.c)."
out_op(i::Int, rd::read_data)::Int = length(rd.op.out_queue) + i + 1

# PORT: pl-read.c pop_out_op
"Pop the out queue's top entry (pl-read.c)."
function pop_out_op(rd::read_data)::Nothing
    pop!(rd.op.out_queue)
    return nothing
end

# PORT: pl-read.c op_name
"The name of the operator `e` (pl-read.c): its atom, or its block's name (`[...]`: `[]`)."
function op_name(e::op_entry{T})::T where {T}
    if !e.isterm
        a = e.atom
        a === nothing && error("read/1: an operator without a name")    # (never: name_token)
        return a
    end
    b = e.block
    b === nothing && error("read/1: a block operator without its block")
    # PL_get_name_arity(e->op.block, &name, NULL)
    name = kind(b) === EXPR ? child(b, 1) : b
    kind(name) === SYM || error("read/1: a block operator's name")     # assert(0)
    if sym_key(name) == sym_key(mk_sym(T, LIST_CONS_NAME))              # ATOM_dot
        name = mk_nil(T)
    end
    return name
end

# PORT: pl-read.c build_op_term
# DIVERGES: no term positions; upstream's unused `tmp` term reference is not made.
"Build the term of operator `op` from its operands on the term stack (pl-read.c)."
function build_op_term(op::op_entry{T}, rd::read_data{T})::Bool where {T}
    arity = op.kind == OP_INFIX ? 2 : 1
    e = out_op(-arity, rd)
    if !op.isblock
        build_term(op_name(op), arity, rd) || return false
    else
        term = alloc_term(rd)
        av = term_av(-(arity + 1), rd)
        ts = rd.term_stack
        for i in arity:-1:1                         # av[i] = av[i-1]
            ts.terms[av + i] = ts.terms[av + i - 1]
            ts.vars[av + i] = ts.vars[av + i - 1]
        end
        @assert term == av + arity
        b = op.block
        b === nothing && error("read/1: a block operator without its block")
        _setHandle!(av, b, rd)                      # av[0] = term; PL_put_term(term, op->op.block)
        build_term(op_name(op), arity + 1, rd) || return false
    end
    q = rd.op.out_queue
    q[e] = out_entry(op.op_pri)                     # e->pri = op->op_pri
    resize!(q, e)                                   # out_queue.top = e+1
    return true
end

# ── the parser (pl-read.c) ──────────────────────────────────────────────────────────────────────

# PORT: pl-read.c cterm_state
# DIVERGES: a mutable record, copied (`copy_cterm_state`) where upstream copies the struct.
"The state of one level of `complex_term` (pl-read.c): its entries on the two queues."
mutable struct cterm_state{T}
    rd::read_data{T}                # Read global data
    out_n::Int                      # entries in out queue
    side_n::Int                     # entries in side queue
    side_p::Int                     # top (index) of side queue
    rmo::Int                        # Operands more than operators
end

# A copy of `c`: upstream copies the struct by value (a frame's `cstate`).
copy_cterm_state(c::cterm_state{T}) where {T} =
    cterm_state{T}(c.rd, c.out_n, c.side_n, c.side_p, c.rmo)

# PORT: pl-read.c pf_kind
"A compound construct `complex_term` reads in a frame of its own (pl-read.c)."
@enum pf_kind::UInt8 begin
    PF_NONE = 0                     # not a compound construct
    PF_COMPOUND                     # f(a1, ...)
    PF_BLOB                         # <type>(...)
    PF_LIST_ELEM                    # [a1, ... : element
    PF_LIST_TAIL                    # [a1|Tail] : after the `|'
    PF_DICT                         # Tag{k:v, ...}
    PF_BRACKET                      # {...}, (...) and e.g. «...»
    PF_QQ                           # {|Type||...|} : the type
end

# PORT: pl-read.c pf_after
"What to do with the term a completed construct produced (pl-read.c)."
@enum pf_after::UInt8 begin
    AF_OPERAND = 0                  # operand of the suspended level
    AF_PREFIX_OP                    # [..]/{..} as prefix operator
    AF_INFIX_OP                     # ... as infix operator
    AF_POSTFIX_OP                   # ... as postfix operator
end

# PORT: pl-read.c reduce_side
"Which side of an operator a reduction is for (pl-read.c)."
@enum reduce_side::UInt8 begin
    REDUCE_LEFT
    REDUCE_RIGHT
end

# PORT: pl-read.c ct_request
# DIVERGES: no positions (refused, R1's decision); `stop` is the String of stop characters,
# `nothing` for the full stop.
"A request from a construct's `_start`/`_resume` function to read a subterm (pl-read.c)."
mutable struct ct_request
    stop::Union{Nothing, String}    # stop at one of these characters
    maxpri::Int                     # max priority of the subterm
end

# PORT: pl-read.c pframe
# DIVERGES: no positions (`positions`, `pin`, the members' `pv`: refused, R1's decision); the
# union's members are fields. A LIST keeps its elements (`list_elements`) and is built when it ends,
# where upstream extends it cell by cell through a reference to its tail (`tail`); each element is
# made a value (`readValHandle`) where upstream places it, so the variables' order holds, and the
# list's own entry on the term stack (`list_term`) is where upstream's first cell goes. Blobs, dicts
# and quasi-quotations are refused (R1's decision): their members are absent.
"A suspended level of `complex_term` (pl-read.c): its arguments, queue state and construct."
mutable struct pframe{T}
    stop::Union{Nothing, String}    # complex_term() arguments
    cstate::cterm_state{T}          # out/side queue state
    in_op::op_entry{T}              # if after != AF_OPERAND
    maxpri::Int
    red_op::Int                     # AF_POSTFIX_OP: side queue index
    kind::pf_kind                   # pf_kind
    after::pf_after                 # pf_after
    red_side::reduce_side           # AF_POSTFIX_OP: reduce_side
    compound_functor::Union{Nothing, T}     # u.compound.functor
    compound_arity::Int                     # u.compound.arity
    list_term::Int                          # u.list.tail: the list's term-stack entry
    list_elements::Vector{T}                # (the elements read so far)
    bracket_functor::Union{Nothing, T}      # u.bracket.functor: ATOM_curl or 0
    bracket_open::Int                       # paired: open and close
    bracket_close::Int
    bracket_stop::String                    # UTF-8 of close; see ct_request
end

# PORT: pl-read.c CTR_SUB
"A construct's request to read the subterm in its `ct_request` (pl-read.c)."
const CTR_SUB = 2

# PORT: pl-read.c isOp
# DIVERGES: the module is the read data's index into `gd`'s table.
"Is `e`'s name an operator of `kind` (pl-read.c)? Then its type and priorities are set in `e`."
function isOp(e::op_entry{T}, kind::Int, rd::read_data{T})::Bool where {T}
    gd = rd.gd
    ok, type, pri16 = currentOperator(gd, gd.modules[rd.module_], op_name(e), kind)
    ok || return false
    pri = Int(pri16)
    e.type = type
    e.kind = kind
    e.op_pri = pri

    if type == OP_FX
        e.left_pri = 0
        e.right_pri = pri - 1
    elseif type == OP_FY
        e.left_pri = 0
        e.right_pri = pri
    elseif type == OP_XF
        e.left_pri = pri - 1
        e.right_pri = 0
    elseif type == OP_YF
        e.left_pri = pri
        e.right_pri = 0
    elseif type == OP_XFX
        e.left_pri = pri - 1
        e.right_pri = pri - 1
    elseif type == OP_XFY
        e.left_pri = pri - 1
        e.right_pri = pri
    elseif type == OP_YFX
        e.left_pri = pri
        e.right_pri = pri - 1
    end
    return true
end

# PORT: pl-read.c PopOp as PopOp!
"Pop the side queue's top operator, which is this level's (pl-read.c `PopOp`)."
function PopOp!(cstate::cterm_state)::Nothing
    pop_side_op(cstate.rd)
    cstate.side_n -= 1
    cstate.side_p -= 1
    return nothing
end

# PORT: pl-read.c modify_op
"""
Where two operands would follow each other, take the side queue's top operator as an atom
(a prefix one) or as a postfix one (an infix one that is also postfix) (pl-read.c).
"""
function modify_op(cstate::cterm_state{T}, cpri::Int)::Bool where {T}
    rd = cstate.rd
    if cstate.side_n > 0 && cstate.rmo == 0 && cpri > side_op(cstate.side_p, rd).right_pri
        op = side_op(cstate.side_p, rd)
        if op.kind == OP_PREFIX
            cstate.rmo += 1
            tmp = alloc_term(rd)
            if op.isblock
                b = op.block
                b === nothing && error("read/1: a block operator without its block")
                _setHandle!(tmp, b, rd)             # PL_put_term(tmp, op->op.block)
            else
                _setHandle!(tmp, op_name(op), rd)   # PL_put_atom(tmp, op->op.atom)
            end
            queue_out_op(0, rd)
            cstate.out_n += 1
            PopOp!(cstate)
        elseif op.kind == OP_INFIX && cstate.out_n > 0 && isOp(op, OP_POSTFIX, rd)
            cstate.rmo += 1
            build_op_term(op, rd) || return false
            PopOp!(cstate)
        end
    end
    return true
end

# PORT: pl-read.c bad_operator
# DIVERGES: `out` is the index of the operator's first operand on the out queue; the position moves
# past the operator's name by its UTF-8 length, where upstream adds the length of its stored text
# (ISO Latin-1 for an atom with no wider character): the two differ for a non-ASCII name only.
"Raise `operator_clash` at the operator `op` (pl-read.c); false, always."
function bad_operator(out::Int, op::op_entry{T}, rd::read_data{T})::Bool where {T}
    opname = sym_text(op_name(op))                  # stringOp(op)
    rd.token_start = op.token_start
    if op.kind == OP_INFIX
        if op.left_pri < rd.op.out_queue[out].pri
            # t = out[0].term
        else
            rd.token_start += ncodeunits(opname)    # t = out[1].term
        end
    elseif op.kind == OP_PREFIX
        rd.token_start += ncodeunits(opname)
    end
    return syntaxError("operator_clash", rd)
end

# PORT: pl-read.c can_reduce
"""
Can the operator `op` be reduced with its operands (pl-read.c): 1 if so, 0 if not, -1 for a
syntax error (`operator_clash`: it cannot, and the context `cpri` is the outermost one).
"""
function can_reduce(op::op_entry{T}, cpri::Int, out_n::Int, rd::read_data{T})::Int where {T}
    arity = op.kind == OP_INFIX ? 2 : 1
    e = out_op(-arity, rd)
    q = rd.op.out_queue
    rc = false
    if arity <= out_n
        if op.kind == OP_PREFIX
            rc = op.right_pri >= q[e].pri
        elseif op.kind == OP_POSTFIX
            rc = op.left_pri >= q[e].pri
        elseif op.kind == OP_INFIX
            rc = op.left_pri >= q[e].pri && op.right_pri >= q[e + 1].pri
        else
            @assert false "can_reduce: an operator of no kind"
            rc = false
        end
    else
        return 0
    end

    if rc == false && cpri == OP_MAXPRIORITY + 1
        bad_operator(e, op, rd)
        return -1
    end
    return rc ? 1 : 0
end

# PORT: pl-read.c must_reduce
"Must the side operator `sop` be reduced before `fop` takes its `side` (pl-read.c)?"
function must_reduce(sop::op_entry{T}, fop::op_entry{T}, side::reduce_side)::Bool where {T}
    cpri = side == REDUCE_LEFT ? fop.left_pri : fop.right_pri
    if cpri == sop.op_pri
        # Deal with `fy 2 yf`, `1 xfy 2 yfx 3`, etc.
        if (
            (sop.kind == OP_PREFIX || sop.kind == OP_INFIX) && sop.op_pri == sop.right_pri
        ) &&
            ((fop.kind == OP_POSTFIX || fop.kind == OP_INFIX) && fop.op_pri == fop.left_pri)
            return false
        end
    end
    return cpri >= sop.op_pri
end

# PORT: pl-read.c reduce_one_op
"Reduce the side queue's top operator if `op`'s `side` requires it (pl-read.c): 1, 0, or -1 on an error."
function reduce_one_op(
    cstate::cterm_state{T}, op::op_entry{T}, side::reduce_side
)::Int where {T}
    rd = cstate.rd
    cpri = side == REDUCE_LEFT ? op.left_pri : op.right_pri
    if cstate.out_n > 0 && cstate.side_n > 0
        sop = side_op(cstate.side_p, rd)
        if must_reduce(sop, op, side)
            rc = can_reduce(sop, cpri, cstate.out_n, cstate.rd)
            if rc > 0
                build_op_term(sop, cstate.rd) || return -1
                sop.kind == OP_INFIX && (cstate.out_n -= 1)
                PopOp!(cstate)
            end
            return rc
        end
    end
    return 0
end

# PORT: pl-read.c reduce_op
"Reduce the side queue as far as the left side of `op` requires (pl-read.c); false on an error."
function reduce_op(cstate::cterm_state{T}, op::op_entry{T})::Bool where {T}
    rc = reduce_one_op(cstate, op, REDUCE_LEFT)
    while rc == 1
        rc = reduce_one_op(cstate, op, REDUCE_LEFT)
    end
    return rc == 0                                  # false --> true, -1 --> false
end

# The atom value of a name token (upstream reads the union: never empty for these tokens).
function _token_atom(token::token{T})::T where {T}
    a = token.atom
    a === nothing && error("read/1: a name token without its atom")
    return a
end

# PORT: pl-read.c is_name_token
"""
May `token` be an operator's name (pl-read.c): 1 if so, 0 if not, -1 for a syntax error
(`cannot_start_term`, or `|` where an operand must come: `quoted_punctuation`).
"""
function is_name_token(token::token{T}, must_be_op::Bool, rd::read_data{T})::Int where {T}
    t = token.type
    if t == TK_NAME
        return 1
    elseif t == TK_QNAME
        return unquoted_atom(_token_atom(token)) ? 0 : 1    # GD->options.traditional: off
    elseif t == TK_FUNCTOR || t == TK_DICT
        return must_be_op ? 1 : 0
    elseif t == TK_PUNCTUATION
        c = token.character
        if c == Int('[') || c == Int('{')
            return 1
        elseif c == Int('(')
            return 0
        elseif c == Int(')') || c == Int('}') || c == Int(']')
            errorWarning("cannot_start_term", nothing, rd)
            return -1
        elseif c == Int('|')
            if !must_be_op
                errorWarning("quoted_punctuation", nothing, rd)
                return -1
            end
            return 1
        end
        return 1
    end
    return 0
end

# PORT: pl-read.c name_token
"The atom a name token stands for (pl-read.c); `[` and `{` make `e` a block operator."
function name_token(
    token::token{T}, e::Union{Nothing, op_entry{T}}, rd::read_data{T}
)::T where {T}
    t = token.type
    if t == TK_PUNCTUATION
        c = token.character
        if c == Int('[')
            e !== nothing && (e.isblock = true)
            return mk_nil(T)                        # ATOM_nil
        elseif c == Int('{')
            e !== nothing && (e.isblock = true)
            return mk_sym(T, Symbol("{}"))          # ATOM_curl
        end
        return mk_sym(T, Symbol(Char(c)))           # codeToAtom()
    elseif t == TK_FULLSTOP
        return mk_sym(T, Symbol("."))               # codeToAtom('.'): ATOM_dot can be [|]
    end
    return _token_atom(token)
end

# PORT: pl-read.c prepare_op
# DIVERGES: returns the result and the construct to read (`*kind`); no positions; no atom locks
# (`Unlock`: no atom GC).
"""
Take `token` as the name of the operator `in_op` (pl-read.c); a block operator (`[...]`, `{...}`)
starts reading its block: the construct to read is returned with the result.
"""
function prepare_op(
    in_op::op_entry{T}, token::token{T}, rd::read_data{T}
)::Tuple{Int, pf_kind} where {T}
    in_op.isblock && return simple_term(token, rd)
    return (1, PF_NONE)
end

# PORT: pl-read.c finish_block_op
# DIVERGES: the block is the term itself (see `op_entry`).
"Take the block just read off the term stack as the operator `in_op`'s name (pl-read.c)."
function finish_block_op(in_op::op_entry{T}, rd::read_data{T})::Nothing where {T}
    top = term_av(-1, rd)
    in_op.block = _ts_term(top, rd)                 # PL_put_term(in_op->op.block, *top)
    in_op.isterm = true
    truncate_term_stack(top, rd)
    return nothing
end

# PORT: pl-read.c stop_matches_codepoint
"Is `code` one of the characters of `stop` (pl-read.c)?"
function stop_matches_codepoint(stop::String, code::Int)::Bool
    for c in stop
        Int(c) == code && return true
    end
    return false
end

# PORT: pl-read.c complex_term
# DIVERGES: no positions (refused, R1's decision); the segstack is a vector of frames; returns
# upstream's codes as an Int — 1 (true) or 0 (false): no stack-overflow codes (no global stack);
# no atom locks to release (`discard_pframe`). A blob, a dict or a quasi-quotation raises
# `NotPortedError` (`start_pframe`): refused, R1's decision.
"""
Read a term up to a character of `stop` (`nothing`: up to the full stop) with priority at most
`maxpri`, resolving its operators, and leave it on the term stack (pl-read.c). A state machine:
a construct (a compound, a list, a bracketed term) suspends the level in a frame, so nesting
costs no Julia stack. 1 on success, 0 with the syntax error in `rd`.
"""
function complex_term(
    stop::Union{Nothing, String}, maxpri::Int, rd::read_data{T}
)::Int where {T}
    stack = pframe{T}[]
    req = ct_request(nothing, 0)
    in_op = op_entry{T}()
    end_op = op_entry{T}()
    cstate = cterm_state{T}(rd, 0, 0, 0, 0)
    kind = PF_NONE
    after = AF_OPERAND
    red_op = -1                                     # postfix: side queue index
    red_side = REDUCE_LEFT
    rc = 0
    token = rd.token

    @label new_level                                # start reading a (sub) term
    if rd.strictness == 0
        maxpri = OP_MAXPRIORITY + 1
    end
    end_op.left_pri = maxpri
    cstate.rd = rd
    cstate.out_n = 0
    cstate.side_n = 0
    cstate.side_p = side_p0(rd)
    cstate.rmo = 0
    in_op.left_pri = 0
    in_op.right_pri = 0

    @label next_token
    tk = get_token(cstate.rmo == 1, rd)
    tk === nothing && @goto failed
    token = tk

    if cstate.out_n != 0 || cstate.side_n != 0      # Check for end of term
        if token.type == TK_FULLSTOP
            stop === nothing && @goto level_done
        elseif token.type == TK_PUNCTUATION
            stop !== nothing && stop_matches_codepoint(stop, token.character) &&
                @goto level_done
        elseif token.type == TK_QQ_BAR
            stop !== nothing && first(stop) == '|' && @goto level_done
        end
    end

    rc = is_name_token(token, cstate.rmo == 1, rd)
    if rc == 1
        in_op.isblock = false
        in_op.isterm = false
        in_op.atom = name_token(token, in_op, rd)
        in_op.token_start = rd.token_start

        if cstate.rmo == 0 && isOp(in_op, OP_PREFIX, rd)
            rc, kind = prepare_op(in_op, token, rd)
            rc != 1 && @goto failed_rc
            if kind != PF_NONE
                after = AF_PREFIX_OP
                @goto start_frame
            end
            @label prefix_op
            queue_side_op(in_op, rd)                # PushOp()
            cstate.side_n += 1
            cstate.side_p += 1
            @goto next_token
        end
        if isOp(in_op, OP_INFIX, rd)
            modify_op(cstate, in_op.left_pri) || @goto failed
            if cstate.rmo == 1
                reduce_op(cstate, in_op) || @goto failed
                cstate.rmo -= 1
                rc, kind = prepare_op(in_op, token, rd)
                rc != 1 && @goto failed_rc
                if kind != PF_NONE
                    after = AF_INFIX_OP
                    @goto start_frame
                end
                @label infix_op
                queue_side_op(in_op, rd)            # PushOp()
                cstate.side_n += 1
                cstate.side_p += 1
                @goto next_token
            end
        end
        if isOp(in_op, OP_POSTFIX, rd)
            modify_op(cstate, in_op.left_pri) || @goto failed
            if cstate.rmo == 1
                red_op = -1                         # index; the queue may be moved
                red_side = REDUCE_LEFT

                reduce_op(cstate, in_op) || @goto failed

                if cstate.side_n > 0
                    prev = side_op(cstate.side_p, rd)
                    if prev.kind == OP_PREFIX || prev.kind == OP_INFIX
                        red_op = cstate.side_p
                        red_side = REDUCE_RIGHT
                    end
                end

                rc, kind = prepare_op(in_op, token, rd)
                rc != 1 && @goto failed_rc
                if kind != PF_NONE
                    after = AF_POSTFIX_OP
                    @goto start_frame
                end
                @label postfix_op
                queue_side_op(in_op, rd)            # PushOp()
                cstate.side_n += 1
                cstate.side_p += 1
                if reduce_one_op(
                    cstate, red_op < 0 ? end_op : side_op(red_op, rd), red_side
                ) == -1
                    @goto failed
                end
                @goto next_token
            end
        end
    elseif rc < 0
        @goto failed
    end

    if cstate.rmo == 1
        errorWarning("operator_expected", nothing, rd)      # ctSyntaxError()
        @goto failed
    end

    # Read `simple' term
    rc, kind = simple_term(token, rd)
    rc != 1 && @goto failed_rc
    if kind != PF_NONE                              # a compound construct
        after = AF_OPERAND
        @goto start_frame
    end

    @label operand                                  # term is on the term stack
    if cstate.rmo != 0
        errorWarning("operator_expected", nothing, rd)      # ctSyntaxError()
        @goto failed
    end
    cstate.rmo += 1
    queue_out_op(0, rd)
    cstate.out_n += 1
    @goto next_token

    @label start_frame                              # suspend and read `kind'
    push!(
        stack,
        pframe{T}(
            stop, copy_cterm_state(cstate), copy_op_entry(in_op), maxpri, red_op, kind,
            after,
            red_side, nothing, 0, 0, T[], nothing, 0, 0, ""
        )
    )
    rc = start_pframe(stack[end], token, req, rd)
    rc == CTR_SUB && @goto sub_term
    rc != 1 && @goto failed_rc
    @goto frame_done

    @label sub_term                                 # read the subterm in `req'
    stop = req.stop
    maxpri = req.maxpri
    @goto new_level

    @label frame_done                               # construct is on the term stack
    if isempty(stack)
        @assert false "complex_term: no frame to pop"
        @goto failed
    end
    frame = pop!(stack)
    stop = frame.stop
    maxpri = frame.maxpri
    cstate = frame.cstate
    end_op.left_pri = maxpri

    frame.after == AF_OPERAND && @goto operand

    in_op = frame.in_op                             # [..]/{..} used as operator
    finish_block_op(in_op, rd)
    frame.after == AF_PREFIX_OP && @goto prefix_op
    frame.after == AF_INFIX_OP && @goto infix_op
    red_op = frame.red_op
    red_side = frame.red_side
    @goto postfix_op

    @label level_done                               # complete the current level
    rd._unget = true                                # unget_token(): the full-stop or punctuation
    modify_op(cstate, maxpri) || @goto failed
    reduce_op(cstate, end_op) || @goto failed

    if cstate.out_n == 1 && cstate.side_n == 0      # simple term
        pop_out_op(rd)                              # PopOut()
        cstate.out_n -= 1
    elseif cstate.out_n == 0 && cstate.side_n == 1  # single operator
        op = side_op(cstate.side_p, rd)
        term = alloc_term(rd)
        if !op.isblock
            _setHandle!(term, op_name(op), rd)      # PL_put_atom(term, op->op.atom)
        else
            b = op.block
            b === nothing && error("read/1: a block operator without its block")
            _setHandle!(term, b, rd)                # PL_put_term(term, op->op.block)
        end
        PopOp!(cstate)
    elseif cstate.side_n == 1 && !side_op(0, rd).isblock &&
        (
            sym_key(op_name(side_op(0, rd))) == sym_key(mk_sym(T, Symbol(","))) ||
            sym_key(op_name(side_op(0, rd))) == sym_key(mk_sym(T, Symbol(";")))
        )
        # (as upstream: the queue's entry 0, then this level's top for the error)
        rd.ld.exception_processing = true
        ex = mk_expr(
            T,
            T[mk_sym(T, :punct), op_name(side_op(cstate.side_p, rd)),
                name_token(token, nothing, rd)]
        )
        errorWarning("", ex, rd)
        @goto failed
    else
        errorWarning("operator_balance", nothing, rd)       # ctSyntaxError()
        @goto failed
    end

    # term is on the term stack
    isempty(stack) && return 1                      # we completed the whole term

    rc = resume_pframe(stack[end], req, rd)
    rc == CTR_SUB && @goto sub_term
    rc != 1 && @goto failed_rc
    @goto frame_done

    @label failed
    rc = 0
    @label failed_rc
    empty!(stack)                                   # discard_pframe(): no atom locks
    return rc
end

# ── the constructs: lists, brackets, compounds (pl-read.c) ──────────────────────────────────────

# PORT: pl-read.c read_list_elem
"Request a list element (pl-read.c)."
function read_list_elem(f::pframe{T}, req::ct_request, rd::read_data{T})::Int where {T}
    f.kind = PF_LIST_ELEM
    req.stop = ",|]"
    req.maxpri = 999
    return CTR_SUB
end

# PORT: pl-read.c read_list_start
# DIVERGES: the list's term-stack entry is kept (`list_term`), where upstream keeps a reference to
# where the tail goes (`tail`); no positions.
"Start reading a list, at its `[` (pl-read.c)."
function read_list_start(
    f::pframe{T}, token::token{T}, req::ct_request, rd::read_data{T}
)::Int where {T}
    term = alloc_term(rd)
    f.list_term = term                              # PL_put_term(tail, term)
    empty!(f.list_elements)
    return read_list_elem(f, req, rd)
end

# PORT: pl-read.c read_list_resume_elem
# DIVERGES: the element is made a value (`readValHandle`) and kept, where upstream writes it into
# a new cell at the tail; at `]` the list is made (`PL_unify_nil(tail)`). No positions.
"Take the element just read; then `]` ends the list, `|` requests its tail, `,` another element (pl-read.c)."
function read_list_resume_elem(
    f::pframe{T}, req::ct_request, rd::read_data{T}
)::Int where {T}
    tmp = term_av(-1, rd)
    push!(f.list_elements, readValHandle(tmp, rd))
    truncate_term_stack(tmp, rd)

    tk = get_token(false, rd)
    tk === nothing && return 0

    c = tk.character
    if c == Int(']')
        _setHandle!(f.list_term, _read_list_term(f.list_elements, mk_nil(T)), rd)
        return 1
    elseif c == Int('|')
        f.kind = PF_LIST_TAIL
        req.stop = ",|]"
        req.maxpri = 999
        return CTR_SUB
    end
    return read_list_elem(f, req, rd)               # `,'
end

# PORT: pl-read.c read_list_resume_tail
# DIVERGES: the list is made with the tail just read, where upstream writes the tail into its last
# cell. No positions.
"Take the tail just read and end the list at its `]` (pl-read.c): `,` or `|` there is `list_rest`."
function read_list_resume_tail(f::pframe{T}, rd::read_data{T})::Int where {T}
    tmp = term_av(-1, rd)
    tail = readValHandle(tmp, rd)
    truncate_term_stack(tmp, rd)
    tk = get_token(false, rd)                       # discard ']'
    tk === nothing && return 0
    if tk.character == Int(',') || tk.character == Int('|')
        return Int(syntaxError("list_rest", rd))
    end
    _setHandle!(f.list_term, _read_list_term(f.list_elements, tail), rd)
    return 1
end

# PORT: pl-read.c read_bracket_start
# DIVERGES: no positions.
"Start reading `(Term)`, `{Term}` or a Unicode bracket pair's `«Term»` (pl-read.c)."
function read_bracket_start(
    f::pframe{T}, token::token{T}, req::ct_request, rd::read_data{T}
)::Int where {T}
    c = token.character
    f.bracket_functor = nothing
    f.bracket_open = 0
    f.bracket_close = 0

    if c == Int('(')
        req.stop = ")"
    elseif c == Int('{')
        f.bracket_functor = mk_sym(T, Symbol("{}"))     # ATOM_curl
        req.stop = "}"
    else                                            # Unicode bracket/quote pair
        close, _ = pl_pair_lookup(c)
        close == 0 && return Int(syntaxError("illegal_character", rd))
        f.bracket_open = c
        f.bracket_close = close
        f.bracket_stop = string(Char(close))        # UTF-8 of the closing delimiter
        req.stop = f.bracket_stop
    end

    req.maxpri = OP_MAXPRIORITY + 1
    return CTR_SUB
end

# PORT: pl-read.c read_bracket_resume
# DIVERGES: no positions.
"End a bracketed term at its close: `{Term}` is `'{}'(Term)`, `«Term»` is `'«»'(Term)` (pl-read.c)."
function read_bracket_resume(f::pframe{T}, rd::read_data{T})::Int where {T}
    tk = get_token(false, rd)                       # skip ')', '}' or the close
    tk === nothing && return 0

    fn = f.bracket_functor
    fn !== nothing && return build_term(fn, 1, rd) ? 1 : 0     # {Term}

    if f.bracket_open != 0                          # «Term»
        functor = _atom_from_text(T, string(Char(f.bracket_open), Char(f.bracket_close)))
        return build_term(functor, 1, rd) ? 1 : 0
    end
    return 1                                        # (Term)
end

# PORT: pl-read.c read_compound_end
# DIVERGES: no positions; no atom locks (`unlock`).
"Build the compound read (pl-read.c)."
function read_compound_end(f::pframe{T}, token::token{T}, rd::read_data{T})::Int where {T}
    functor = f.compound_functor
    functor === nothing && error("read/1: a compound without its name")
    if rd.dotlists && sym_key(functor) == sym_key(mk_sym(T, Symbol(".")))
        functor = mk_sym(T, LIST_CONS_NAME)         # ATOM_dot: the abstract cons name
    end
    return build_term(functor, f.compound_arity, rd) ? 1 : 0
end

# PORT: pl-read.c read_compound_arg
# DIVERGES: no positions.
"Request a compound's argument (pl-read.c)."
function read_compound_arg(f::pframe{T}, req::ct_request, rd::read_data{T})::Int where {T}
    req.stop = ",)"
    req.maxpri = 999
    return CTR_SUB
end

# PORT: pl-read.c read_compound_start
# DIVERGES: no positions; no atom locks (`unlock`, `rd->locked`).
"Start reading `f(…)` at its name: `f()` ends at once (pl-read.c)."
function read_compound_start(
    f::pframe{T}, token::token{T}, req::ct_request, rd::read_data{T}
)::Int where {T}
    f.compound_functor = _token_atom(token)
    f.compound_arity = 0

    get_token(false, rd) === nothing && return 0    # gets '('
    tk = get_token(false, rd)                       # first token
    tk === nothing && return 0

    if tk.type == TK_PUNCTUATION && tk.character == Int(')')
        return read_compound_end(f, tk, rd)
    end

    rd._unget = true                                # unget_token()
    return read_compound_arg(f, req, rd)
end

# PORT: pl-read.c read_compound_resume
"Count the argument just read; then `)` ends the compound, `,` requests another (pl-read.c)."
function read_compound_resume(
    f::pframe{T}, req::ct_request, rd::read_data{T}
)::Int where {T}
    f.compound_arity += 1
    tk = get_token(false, rd)                       # `,' or `)'
    tk === nothing && return 0
    tk.character == Int(')') && return read_compound_end(f, tk, rd)
    return read_compound_arg(f, req, rd)
end

# PORT: pl-read.c simple_term
# DIVERGES: returns the result and the construct to read (`*kind`); no positions; no atom locks.
"""
Read the term `token` starts, other than an operator expression (pl-read.c): an atomic term or a
variable is left on the term stack (construct `PF_NONE`); a compound construct is returned for
`complex_term` to read. `(0, …)` with the syntax error in `rd`.
"""
function simple_term(token::token{T}, rd::read_data{T})::Tuple{Int, pf_kind} where {T}
    t = token.type
    if t == TK_FULLSTOP
        return (Int(syntaxError("end_of_clause", rd)), PF_NONE)
    elseif t == TK_VOID
        alloc_term(rd)                              # nothing to do; term is already a variable
        return (1, PF_NONE)
    elseif t == TK_VARIABLE
        term = alloc_term(rd)
        rd.term_stack.vars[term] = token.variable   # setHandle(term, var->signature)
        return (1, PF_NONE)
    elseif t == TK_NAME || t == TK_QNAME
        term = alloc_term(rd)
        _setHandle!(term, _token_atom(token), rd)   # PL_put_atom(term, token->value.atom)
        return (1, PF_NONE)
    elseif t == TK_NUMBER
        term = alloc_term(rd)
        _setHandle!(term, put_number(T, token.number), rd)  # _PL_put_number()
        clearNumber(token.number)
        return (1, PF_NONE)
    elseif t == TK_STRING
        term = alloc_term(rd)
        v = token.term_value
        v === nothing && error("read/1: a string token without its term")
        _setHandle!(term, v, rd)                    # PL_put_term(term, token->value.term)
        return (1, PF_NONE)
    elseif t == TK_FUNCTOR
        return (1, PF_COMPOUND)
    elseif t == TK_BLOB
        return (1, PF_BLOB)
    elseif t == TK_DICT || t == TK_VCLASS_DICT || t == TK_VOID_DICT
        return (1, PF_DICT)
    elseif t == TK_PUNCTUATION
        c = token.character
        if c == Int('(') || c == Int('{')
            return (1, PF_BRACKET)
        elseif c == Int('[')
            return (1, PF_LIST_ELEM)
        elseif c == Int(',')
            return (Int(errorWarning("quoted_punctuation", nothing, rd)), PF_NONE)
        end
        close, is_open = pl_pair_lookup(c)
        close != 0 && is_open && return (1, PF_BRACKET)
        term = alloc_term(rd)
        _setHandle!(term, mk_sym(T, Symbol(Char(c))), rd)  # PL_put_atom(term, codeToAtom(c))
        return (1, PF_NONE)
    elseif t == TK_QQ_OPEN
        return (1, PF_QQ)
    elseif t == TK_QQ_BAR
        return (Int(syntaxError("double_bar_outside_quasiquotation", rd)), PF_NONE)
    end
    error("read/1: Illegal token type ($(Int(t)))")    # sysError()
end

# PORT: pl-read.c start_pframe
# DIVERGES: a blob (`<type>(…)`, read only with the blob option), a dict (`Tag{…}`) or a
# quasi-quotation (`{|Syntax||Quotation|}`) raises `NotPortedError`: refused, R1's decision (user,
# 2026-10-07: an explicit error, never a misread). Where swipl raises a SYNTAX error inside one of
# them (`-{a}`, a dict: `colon_expected`), the kernel's refusal comes first.
"Start reading the construct `f.kind` (pl-read.c): `CTR_SUB` for a subterm, 1 if complete, 0 on an error."
function start_pframe(
    f::pframe{T}, token::token{T}, req::ct_request, rd::read_data{T}
)::Int where {T}
    k = f.kind
    if k == PF_COMPOUND
        return read_compound_start(f, token, req, rd)
    elseif k == PF_LIST_ELEM
        return read_list_start(f, token, req, rd)
    elseif k == PF_BRACKET
        return read_bracket_start(f, token, req, rd)
    elseif k == PF_BLOB
        throw(
            NotPortedError{Nothing}(
                nothing, "read: a blob <type>(…)", "the blob read option"
            )
        )
    elseif k == PF_DICT
        throw(
            NotPortedError{Nothing}(
                nothing, "read: a dict Tag{…}", "none: dicts are refused (R1's decision)"
            )
        )
    elseif k == PF_QQ
        throw(
            NotPortedError{Nothing}(
                nothing, "read: a quasi-quotation {|Syntax||Quotation|}",
                "none: quasi-quotations are refused (R1's decision)"
            )
        )
    end
    @assert false "start_pframe: no construct"
    return 0
end

# PORT: pl-read.c resume_pframe
"Continue the construct `f.kind` after its subterm (pl-read.c): `CTR_SUB`, 1 if complete, 0 on an error."
function resume_pframe(f::pframe{T}, req::ct_request, rd::read_data{T})::Int where {T}
    k = f.kind
    if k == PF_COMPOUND
        return read_compound_resume(f, req, rd)
    elseif k == PF_LIST_ELEM
        return read_list_resume_elem(f, req, rd)
    elseif k == PF_LIST_TAIL
        return read_list_resume_tail(f, rd)
    elseif k == PF_BRACKET
        return read_bracket_resume(f, rd)
    end
    @assert false "resume_pframe: a construct that was refused at its start"
    return 0
end

# ── reading a term (pl-read.c) ──────────────────────────────────────────────────────────────────

# PORT: pl-read.c isAnonVarName
"Is the variable name `n` an anonymous variable's (pl-read.c)?"
isAnonVarName(n::Vector{UInt8})::Bool = isAnonVarNameN(n, 1, length(n))

# PORT: pl-read.c bind_variable_names
# DIVERGES: the list `[Name = Var, …]` is made and unified once, where upstream unifies it cell by
# cell; a failure fails the read either way.
"Unify the `variable_names` term with `[Name = Var, …]` of the named variables read (pl-read.c)."
function bind_variable_names(rd::read_data{T})::Bool where {T}
    ld = rd.ld
    pairs = T[]
    for var in rd.vt.var_buffer
        if !isAnonVarName(var.name)
            push!(
                pairs,
                mk_expr(
                    T,
                    T[mk_sym(T, :(=)), _atom_from_text(T, String(copy(var.name))),
                        ld.slots[var.variable + 1]]
                )
            )
        end
    end
    return unify_ptrs(ld, ld.slots[rd.varnames + 1], _read_list_term(pairs, mk_nil(T)))
end

# PORT: pl-read.c bind_variables
"Unify the `variables` term with the list of the variables read (pl-read.c)."
function bind_variables(rd::read_data{T})::Bool where {T}
    ld = rd.ld
    vars = T[ld.slots[var.variable + 1] for var in rd.vt.var_buffer]    # FOR_VARS(var)
    return unify_ptrs(ld, ld.slots[rd.variables + 1], _read_list_term(vars, mk_nil(T)))
end

# PORT: pl-read.c read_term
# DIVERGES: `cycles(true)` (`instantiate_template`) is NOT PORTED — no `@(Template, Bindings)`
# is ever read into a cycle (R1e decision 4a refuses cyclic terms; the option is accepted and does
# nothing, as it does for a text without one); no quasi-quotations to parse
# (`parse_quasi_quotations`: one is refused before it is collected); no overflow codes
# (`raiseStackOverflow`).
"""
Read one term from the read data's stream and unify it with term reference `term` (pl-read.c):
the raw text, the term up to the full stop, then the variable names. False on a syntax error,
which `rd.has_exception` and `rd.exception` hold.
"""
function read_term(term::term_t, rd::read_data{T})::Bool where {T}
    ld = rd.ld
    rc = false
    ok, e = raw_read(rd)
    ok || return false
    rd.end_ = e

    fid = PL_open_foreign_frame(ld)

    rd.here = rd.base
    rd.strictness = 0                               # truePrologFlag(PLFLAG_ISO): off

    rc2 = complex_term(nothing, OP_MAXPRIORITY + 1, rd)
    rc2 != 1 && @goto out                           # rc = raiseStackOverflow(rc2)

    @assert rd.term_stack.top == 1
    result = term_av(-1, rd)
    if rd.term_stack.vars[result] >= 0              # reading a single variable
        _setHandle!(result, readValHandle(result, rd), rd)
    end

    tk = get_token(false, rd)
    tk === nothing && @goto out
    if tk.type != TK_FULLSTOP
        errorWarning("end_of_clause_expected", nothing, rd)
        @goto out
    end

    rc = unify_ptrs(ld, ld.slots[term + 1], _ts_term(result, rd))    # PL_unify(term, result[0])

    truncate_term_stack(result, rd)
    rc || @goto out
    if rd.varnames != 0
        rc = bind_variable_names(rd)
        rc || @goto out
    end
    if rd.variables != 0
        rc = bind_variables(rd)
        rc || @goto out
    end
    if rd.singles != 0
        rc = check_singletons(term, rd)
        rc || @goto out
    end

    rc = true

    @label out
    PL_close_foreign_frame(ld, fid)
    return rc
end

# ── singletons and read_clause (pl-read.c), since R1f ───────────────────────────────────────────

# `rd.singles` when the singletons are only REPORTED: upstream stores `true` (1) in the term_t field;
# here -1, which no term reference is.
const _SINGLES_REPORT = -1

# PORT: pl-read.c MAX_SINGLETONS
"The most singletons reported for one term (pl-read.c)."
const MAX_SINGLETONS = 256

# PORT: pl-read.c IS_SINGLETON
"`is_singleton`'s question: a singleton to warn about (pl-read.c)."
const IS_SINGLETON = 0
# PORT: pl-read.c LIST_SINGLETONS
"`is_singleton`'s question: any singleton (pl-read.c)."
const LIST_SINGLETONS = 1
# PORT: pl-read.c IS_MULTITON
"`is_singleton`'s question: a `_X` variable used more than once (pl-read.c)."
const IS_MULTITON = 2

# PORT: pl-read.c var_name_body
# DIVERGES: the name's bytes; returns the body's start index (2 past a prefix symbol, else 1).
"Where a variable name's body starts: past a var_prefix symbol such as `?` (pl-read.c)."
var_name_body(name::AbstractVector{UInt8})::Int =
    (length(name) >= 2 && (Int(name[1]) % UInt32) < 0x80 && PlSymbolW(Int(name[1]))) ? 2 : 1

# The byte at `i` of a C string `name`, 0 past its end.
_cbyte(name::AbstractVector{UInt8}, i::Int)::Int = i <= length(name) ? Int(name[i]) : 0

# PORT: pl-read.c warn_singleton
# DIVERGES: the name's bytes (UTF-8).
"Should a singleton variable named `name` be reported (pl-read.c)? `_` and `__x` never are."
function warn_singleton(name::AbstractVector{UInt8})::Bool
    b = var_name_body(name)
    prefixed = b != 1
    _cbyte(name, b) != Int('_') && return true      # not _*: always warn
    _cbyte(name, b + 1) == Int('_') && return false # __*: never warn
    if _cbyte(name, b + 1) != 0                     # _a: warn
        _, c = utf8_get_char(name, b + 1)
        isDigitW(c) && return false
        !prefixed && !PlUpperW(c) && return true
    end
    return false
end

# PORT: pl-read.c warn_multiton
# DIVERGES: the name's bytes (UTF-8).
"Should a variable named `name` used more than once be reported (pl-read.c)?"
function warn_multiton(name::AbstractVector{UInt8})::Bool
    if !warn_singleton(name)
        b = var_name_body(name)
        prefixed = b != 1
        if _cbyte(name, b) == Int('_') && _cbyte(name, b + 1) != 0
            _, c = utf8_get_char(name, b + 1)
            isDigitW(c) && return false             # _<digit>: never warn
            !prefixed && !PlUpperW(c) && return false   # _<lower>: never warn
        end
        return true
    end
    return false
end

# PORT: pl-read.c atom_is_named_var
# DIVERGES: the name's bytes (UTF-8), as `warn_singleton`'s — upstream has one branch for a
# single-byte name and one for a wide one, the same tests on the character.
"""
What a variable named `name` is to the style checks (pl-read.c): 1 a properly named variable, 0
neutral (`_<digit>`), -1 anonymous (`_<Upper>`, `__<lower>`, `_`).
"""
function atom_is_named_var(name::AbstractVector{UInt8})::Int       # see warn_singleton()
    b = var_name_body(name)
    prefixed = b != 1
    _cbyte(name, b) != Int('_') && return 1
    if _cbyte(name, b + 1) != 0
        _cbyte(name, b + 1) == Int('_') && return -1
        _, c = utf8_get_char(name, b + 1)
        isDigitW(c) && return 0
        !prefixed && !PlUpperW(c) && return 1
    end
    return -1
end

# PORT: pl-read.c is_singleton
# DIVERGES: no quasi-quotation scan (a quasi-quotation is refused before it is collected).
"Is `var` a singleton (or multiton) of the kind `type` asks (pl-read.c)?"
function is_singleton(var::variable, type::Int, rd::read_data)::Bool
    name = view(var.name, 1:(var.namelen))
    if type == IS_SINGLETON
        return var.times == 1 && warn_singleton(name)
    elseif type == LIST_SINGLETONS
        return var.times == 1
    end
    return var.times > 1 && warn_multiton(name)
end

# PORT: pl-read.c singletonWarning
# DIVERGES: the names are the variables' bytes; the message goes to `printMessage`.
"Report `which(Term, Names)` — `singletons` or `multitons` — as a warning (pl-read.c)."
function singletonWarning(
    term::term_t, which::String, vars::Vector{String}, rd::read_data{T}
)::Bool where {T}
    ld = rd.ld
    names = T[_atom_from_text(T, v) for v in vars]  # PL_unify_chars(h, REP_UTF8|PL_ATOM, …)
    l = mk_nil(T)
    for n in reverse(names)
        l = mk_expr(T, T[mk_sym(T, Symbol("[|]")), n, l])
    end
    return printMessage(
        ld, :warning, mk_expr(T, T[mk_sym(T, Symbol(which)), ld.slots[term + 1], l])
    )
end

# PORT: pl-read.c check_singletons
# DIVERGES: the LIST form (`singletons(S)`: `rd.singles` a term reference) is NOT PORTED — no entry
# point sets the option (`PL_scan_options`) — refused; the report form as upstream.
"Report the singletons (and, with `MULTITON_CHECK`, the multitons) of the term read (pl-read.c)."
function check_singletons(term::term_t, rd::read_data{T})::Bool where {T}
    ld = rd.ld
    if rd.singles != _SINGLES_REPORT                # returns <name> = var bindings
        pairs = T[]
        for var in rd.vt.var_buffer                 # FOR_VARS(var)
            if is_singleton(var, LIST_SINGLETONS, rd)
                push!(
                    pairs,
                    mk_expr(
                        T,
                        T[mk_sym(T, :(=)), _atom_from_text(T, String(copy(var.name))),
                            ld.slots[var.variable + 1]]
                    )
                )
            end
        end
        return unify_ptrs(ld, ld.slots[rd.singles + 1], _read_list_term(pairs, mk_nil(T)))
    end
    singletons = String[]                           # just report
    for var in rd.vt.var_buffer                     # FOR_VARS(var): singletons
        if is_singleton(var, IS_SINGLETON, rd)
            length(singletons) < MAX_SINGLETONS &&
                push!(singletons, String(var.name[1:var.namelen]))
        end
    end
    if !isempty(singletons)
        singletonWarning(term, "singletons", singletons, rd) || return false
    end
    if (rd.styleCheck & MULTITON_CHECK) != 0
        empty!(singletons)                          # multiple _X*
        for var in rd.vt.var_buffer
            if is_singleton(var, IS_MULTITON, rd)
                length(singletons) < MAX_SINGLETONS &&
                    push!(singletons, String(var.name[1:var.namelen]))
            end
        end
        if !isempty(singletons)
            singletonWarning(term, "multitons", singletons, rd) || return false
        end
    end
    return true
end

# PORT: pl-read.c reportReadError
# DIVERGES: the message goes to `printMessage`.
"Handle the syntax error just read as `on_error` says: raise it, or report it; true to read on (pl-read.c)."
function reportReadError(rd::read_data{T})::Bool where {T}
    ld = rd.ld
    rd.on_error === :error && return PL_raise_exception(ld, rd.exception)
    if rd.on_error !== :quiet
        printMessage(ld, :error, ld.slots[rd.exception + 1])
    end
    PL_clear_exception(ld)

    rd.on_error === :dec10 && return true

    return false
end

# PORT: pl-read.c set_module_read_data
# DIVERGES: the module is an index into the database's table; no `var_prefix` (the module flag is
# not ported: 0).
"Read in module `m`: its syntax flags (pl-read.c)."
function set_module_read_data(rd::read_data{T}, m::Int)::Nothing where {T}
    rd.module_ = m
    rd.flags = rd.gd.modules[m].flags
    rd.var_prefix = 0                               # _PL_rd->module->var_prefix
    return nothing
end

# PORT: pl-read.c read_clause_options
"read_clause/3's options, in upstream's order (pl-read.c)."
const read_clause_options = (
    PL_option_t(:variable_names, OPT_TERM),
    PL_option_t(:term_position, OPT_TERM),
    PL_option_t(:subterm_positions, OPT_TERM),
    PL_option_t(:process_comment, OPT_BOOL),
    PL_option_t(:comments, OPT_TERM),
    PL_option_t(:syntax_errors, OPT_ATOM),
    PL_option_t(:unicode_atoms, OPT_ATOM),
    PL_option_t(:blob, OPT_ATOM),
    PL_option_t(:var_prefix, OPT_TERM)
)

# PORT: pl-read.c read_clause
# DIVERGES: of the read options (`PL_scan_options`), `variable_names` and `syntax_errors` are
# honoured (since R1g); the others the kernel cannot honour are REFUSED (`NotPortedError`), as
# `read_term_from_stream`'s: `term_position`, `subterm_positions`, `comments`,
# `process_comment(true)` (term positions and the comment hook: R2 — `prolog:comment_hook/3` is not
# defined, so `process_comment` is false), `var_prefix` (the module flag, R2), `unicode_atoms` (the
# NFC hook), `blob` (no blobs); a stream whose unquoted atoms must be NFC is refused
# (`ensure_unicode_normalize_hook`: no normalizer). The foreign frame is closed before returning,
# where upstream leaves it to its caller's.
"""
Read a clause from `s` into term reference `term`, as consulting a file does (pl-read.c): in the
source module, its singletons reported, a syntax error reported and the next clause read.
"""
function read_clause(
    gd::PL_global_data{T}, ld::PL_local_data{T}, s::IOSTREAM, term::term_t, options::term_t
)::Bool where {T}
    fid = PL_open_foreign_frame(ld)
    fid == 0 && return false

    while true                                      # retry:
        rd = init_read_data(gd, ld, s)
        syntax_errors = :dec10                      # ATOM_dec10

        if options != 0
            vals = PL_scan_options(ld, options, 0, "read_option", read_clause_options)
            if vals === nothing
                PL_close_foreign_frame(ld, fid)
                return false
            end
            rd.varnames = something(vals[1], 0)::Int
            tpos = something(vals[2], 0)::Int
            rd.subtpos = something(vals[3], 0)::Int
            process_comment = vals[4] === nothing ? false : vals[4]::Bool
            opt_comments = something(vals[5], 0)::Int
            vals[6] === nothing || (syntax_errors = Symbol(sym_text(vals[6]::T)))
            opt_unicode_atoms = vals[7]
            opt_blobs = vals[8]
            varprefix = something(vals[9], 0)::Int

            for (v, what) in (
                (tpos, "term_position"), (rd.subtpos, "subterm_positions"),
                (opt_comments, "comments"), (varprefix, "var_prefix")
            )
                if v != 0
                    PL_close_foreign_frame(ld, fid)
                    throw(
                        NotPortedError{T}(
                            ld.slots[v + 1], "read_clause's $what option",
                            "R2 (term positions)"
                        )
                    )
                end
            end
            if process_comment || opt_blobs !== nothing || opt_unicode_atoms !== nothing
                PL_close_foreign_frame(ld, fid)
                throw(
                    NotPortedError{T}(
                        mk_sym(T, :read_clause),
                        "read_clause's process_comment(true), blob or unicode_atoms option",
                        "R2 (the comment hook, the NFC hook); no blobs"
                    )
                )
            end
        end

        if rd.unicode_atoms == S_UATOMS_NFC
            PL_close_foreign_frame(ld, fid)
            throw(
                NotPortedError{T}(
                    mk_sym(T, :read_clause), "unicode_atoms(nfc)", "no normalizer"
                )
            )
        end

        set_module_read_data(rd, ld.modules_source)
        rd.on_error = syntax_errors
        rd.singles = (rd.styleCheck & SINGLETON_CHECK) != 0 ? _SINGLES_REPORT : 0
        rval = read_term(term, rd)
        if !rval && rd.has_exception && reportReadError(rd)
            ld.exception_processing = false
            PL_rewind_foreign_frame(ld, fid)
            continue                                # goto retry (free_read_data: GC)
        end
        PL_close_foreign_frame(ld, fid)
        return rval
    end
end

# ── term <-> atom (pl-read.c) ───────────────────────────────────────────────────────────────────

# PORT: pl-read.c atom_to_term
# DIVERGES: the memory stream's buffer starts empty and grows (upstream's starts as 1024 bytes on
# the C stack); the text is made an atom or a string as `_text_term` makes it (`PL_unify_text`);
# no `LD->read_source` to save (see `setCurrentSourceLocation`).
"""
`atom_to_term/3`, `term_to_atom/2` and `term_string/2`'s common part (pl-read.c): read the term
the text `atom` holds into `term`, binding `bindings` (0: none) to its variables' names.
"""
function atom_to_term(
    ld::PL_local_data{T}, atom::term_t, term::term_t, bindings::term_t, text_type::Int
)::Bool where {T}
    gd = _query_gd(ld)
    if bindings == 0 && PL_is_variable(ld, atom)   # term_to_atom(+, -)
        bufp = Ref{Union{Nothing, Vector{UInt8}}}(nothing)
        bufsize = Ref(0)

        wstream = Sopenmem(bufp, bufsize, "w")
        wstream === nothing && error("atom_to_term: Sopenmem")
        wstream.encoding = ENC_UTF8
        wrval = PL_write_term(gd, ld, wstream, term, 1200, PL_WRT_QUOTED)
        if wrval
            Sflush(wstream)

            b = bufp[]
            bytes = (b === nothing || bufsize[] == 0) ? UInt8[] : b[1:bufsize[]]
            t = _text_term(T, bytes, text_type == PL_ATOM ? :atom : :string)
            wrval = PL_unify_atomic(ld, atom, t)    # PL_unify_text(atom, 0, &txt, text_type)
        end

        Sclose(wstream)

        return wrval
    end

    txt = PL_get_text(ld, atom, CVT_ALL | CVT_EXCEPTION)
    txt === nothing && return false
    stream = Sopen_text(txt, "r")
    stream === nothing && error("atom_to_term: Sopen_text")

    rd = init_read_data(gd, ld, stream)
    if bindings != 0 && (PL_is_variable(ld, bindings) || PL_is_list(ld, bindings))
        rd.varnames = bindings
    elseif bindings != 0
        return PL_error(ld, ERR_TYPE, mk_sym(T, :list), bindings)
    end
    rd.flags |= M_RDSTRING_TERM                     # set(&rd, M_RDSTRING_TERM)

    rval = read_term(term, rd)
    if !rval && rd.has_exception
        rval = PL_raise_exception(ld, rd.exception)
    end
    Sclose(stream)                                  # free_read_data(): Julia's GC

    return rval
end

# PORT: pl-read.c atom_to_term as pl_atom_to_term3_va
# (PRED_IMPL("atom_to_term", 3, atom_to_term, 0))
"`atom_to_term(+Text, -Term, -Bindings)` (pl-read.c)."
function pl_atom_to_term3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    return atom_to_term(ld, A1, A2, A3, PL_ATOM) ? FTRUE : FFALSE
end

# PORT: pl-read.c term_to_atom as pl_term_to_atom2_va
# (PRED_IMPL("term_to_atom", 2, term_to_atom, 0))
"`term_to_atom(?Term, ?Atom)` (pl-read.c): the term read from the text, or written as an atom."
function pl_term_to_atom2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    return atom_to_term(ld, A2, A1, 0, PL_ATOM) ? FTRUE : FFALSE
end

# PORT: pl-read.c term_string as pl_term_string2_va
# (PRED_IMPL("term_string", 2, term_string, 0))
"`term_string(?Term, ?String)` (pl-read.c): the term read from the text, or written as a string."
function pl_term_string2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    return atom_to_term(ld, A2, A1, 0, PL_STRING) ? FTRUE : FFALSE
end

# PORT: pl-read.c read_term_options
"read_term/2,3's and read_term_from_atom/3's options, in upstream's order (pl-read.c)."
const read_term_options = (
    PL_option_t(:variable_names, OPT_TERM),
    PL_option_t(:variables, OPT_TERM),
    PL_option_t(:singletons, OPT_TERM),
    PL_option_t(:term_position, OPT_TERM),
    PL_option_t(:subterm_positions, OPT_TERM),
    PL_option_t(:character_escapes, OPT_BOOL),
    PL_option_t(:var_prefix, OPT_TERM),
    PL_option_t(:double_quotes, OPT_ATOM),
    PL_option_t(:module, OPT_ATOM),
    PL_option_t(:syntax_errors, OPT_ATOM),
    PL_option_t(:back_quotes, OPT_ATOM),
    PL_option_t(:comments, OPT_TERM),
    PL_option_t(:quasi_quotations, OPT_TERM),
    PL_option_t(:cycles, OPT_BOOL),
    PL_option_t(:dotlists, OPT_BOOL),
    PL_option_t(:unicode_atoms, OPT_ATOM),
    PL_option_t(:blob, OPT_ATOM)
)

# PORT: pl-read.c read_term_from_stream
# DIVERGES: the options the kernel cannot honour are REFUSED (`NotPortedError`) where upstream
# honours them: `term_position`, `subterm_positions`, `comments` (term positions: R2),
# `var_prefix` (the module flag, R2), `unicode_atoms` (the NFC hook), `blob` (no blobs),
# `quasi_quotations` (none are read). The module is the kernel's table's; a syntax error is
# reported through `printMessage` (`reportReadError`); the retry on a `dec10` error re-reads from
# the same stream, as upstream. No `free_read_data` (Julia's GC).
"Read a term from `s` into term reference `term` with the read options list `options` holds (pl-read.c)."
function read_term_from_stream(
    gd::PL_global_data{T}, ld::PL_local_data{T}, s::IOSTREAM, term::term_t, options::term_t
)::Bool where {T}
    fid = PL_open_foreign_frame(ld)

    @label retry
    rd = init_read_data(gd, ld, s)

    vals = PL_scan_options(ld, options, 0, "read_option", read_term_options)
    vals === nothing && return false

    rd.varnames = something(vals[1], 0)::Int
    rd.variables = something(vals[2], 0)::Int
    rd.singles = something(vals[3], 0)::Int
    tpos = something(vals[4], 0)::Int
    rd.subtpos = something(vals[5], 0)::Int
    charescapes = vals[6] === nothing ? -1 : Int(vals[6]::Bool)
    varprefix = something(vals[7], 0)::Int
    dq = vals[8]
    mname = vals[9]
    vals[10] === nothing || (rd.on_error = Symbol(sym_text(vals[10]::T)))
    bq = vals[11]
    tcomments = something(vals[12], 0)::Int
    qq = something(vals[13], 0)::Int
    vals[14] === nothing || (rd.cycles = vals[14]::Bool)
    vals[15] === nothing || (rd.dotlists = vals[15]::Bool)
    opt_unicode_atoms = vals[16]
    opt_blobs = vals[17]

    for (v, what) in (
        (tpos, "term_position"), (rd.subtpos, "subterm_positions"), (tcomments, "comments"),
        (varprefix, "var_prefix"), (qq, "quasi_quotations")
    )
        v != 0 && throw(
            NotPortedError{T}(
                ld.slots[v + 1], "read_term's $what option", "R2 (term positions)"
            )
        )
    end
    opt_blobs === nothing || throw(
        NotPortedError{T}(opt_blobs::T, "read_term's blob option", "never (no blobs)")
    )
    opt_unicode_atoms === nothing || throw(
        NotPortedError{T}(
            opt_unicode_atoms::T, "read_term's unicode_atoms option",
            "R2 (the NFC hook)"
        )
    )

    if mname !== nothing
        m = isCurrentModule(gd.modules, mname::T)
        m === nothing && (m = MODULE_user(gd))
        set_module_read_data(rd, m.index)            # rd.module = …; set_module_read_data
    end

    if charescapes != -1
        if charescapes == 1
            rd.flags |= M_CHARESCAPE                # set(&rd, M_CHARESCAPE)
        else
            rd.flags &= ~M_CHARESCAPE
        end
    end
    if dq !== nothing
        f = setDoubleQuotes(ld, dq::T, rd.flags)
        f === nothing && return false
        rd.flags = f
    end
    if bq !== nothing
        f = setBackQuotes(ld, bq::T, rd.flags)
        f === nothing && return false
        rd.flags = f
    end
    if rd.singles != 0
        w = PL_get_atom(ld, rd.singles)
        if w !== nothing && sym_key(w) == sym_key(mk_sym(T, :warning))
            rd.singles = _SINGLES_REPORT            # rd.singles = true
        end
    end

    rval = read_term(term, rd)
    Sferror(s) != 0 && return false

    if !rval
        if rd.has_exception && reportReadError(rd)
            PL_rewind_foreign_frame(ld, fid)
            @goto retry
        end
    end

    return rval
end

# PORT: pl-read.c read_term_from_atom as pl_read_term_from_atom3_va
# (PRED_IMPL("read_term_from_atom", 3, read_term_from_atom, 0))
# DIVERGES: `CVT_LIST` is accepted as upstream (a code or character list); `BUF_STACK` is nothing.
"`read_term_from_atom(+Text, -Term, +Options)` (pl-read.c)."
function pl_read_term_from_atom3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    gd = _query_gd(ld)

    txt = PL_get_text(ld, A1, CVT_ATOM | CVT_STRING | CVT_LIST | CVT_EXCEPTION)
    txt === nothing && return FFALSE

    oldsrc = ld.read_source
    stream = Sopen_text(txt, "r")
    rc = if stream !== nothing
        r = read_term_from_stream(gd, ld, stream, A2, A3)
        Sclose(stream)
        r
    else
        false
    end

    ld.read_source = oldsrc

    return rc ? FTRUE : FFALSE
end

# PORT: pl-read.c BeginPredDefs as PL_predicates_from_read
# DIVERGES: the entries of the predicates the kernel has ported, in upstream's order
# (read:7431-7444). NOT PORTED: read_term/2,3 and read_clause/3 (a stream argument: the stream
# table, R2), `$code_class/2`, `$is_named_var/1`,
# `$qq_open/2` (no quasi-quotations).
"pl-read.c's registration table (`BeginPredDefs(read)`): the ported entries."
const PL_predicates_from_read = (
    PL_extension("read_term_from_atom", 3, pl_read_term_from_atom3_va, PL_FA_VARARGS),
    PL_extension("atom_to_term", 3, pl_atom_to_term3_va, PL_FA_VARARGS),
    PL_extension("term_to_atom", 2, pl_term_to_atom2_va, PL_FA_VARARGS),
    PL_extension("term_string", 2, pl_term_string2_va, PL_FA_VARARGS)
)
