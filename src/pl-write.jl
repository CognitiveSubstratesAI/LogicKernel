# UPSTREAM: swipl-devel src/pl-write.c @ bae881a2
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2026, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# THE WRITER (R1e). Since R1c the NaN helpers the reader needs to read `1.5NaN`: a NaN's payload
# is written as the float whose exponent field is replaced (`NaN_value`), and read back by putting
# the NaN exponent into it (`make_nan`). Since R1d the quoting rules the parser asks of a quoted
# name (`unquoted_atom`: may it be written without quotes? then it is no operator). Since R1e's
# CORE (user, 2026-10-07, decision 1b) the writer itself: the quoting rules with write options, the
# token layer that keeps tokens apart (`needSpace`, `PutOpenToken`, `PutToken`), atoms, strings,
# integers and rationals, `'$VAR'` terms, and `writeTerm2`'s state machine over an explicit stack —
# operators, lists, `{}`, Unicode bracket pairs, canonical compounds — and `PL_write_term`, which
# `term_to_atom/2` and `term_string/2` write with (src/pl-read.jl). REFUSED (`NotPortedError`): a
# cyclic term (decision 4a), `user:portray/1` when it is defined (decision 3a), a float (R1e's
# floats). NOT PORTED, the rest of R1e: `format_float`, `write/1`, `writeq/1`, `print/1`,
# `write_canonical/1`, `write_term/2,3` and their options, `nl/0,1`; never: attributed variables,
# dicts, blobs other than the reserved symbols.

# PORT: pl-write.c NaN_value
# DIVERGES: the exponent field is replaced on the bits (`reinterpret`), where upstream writes it
# through a union's bit-fields.
"The float whose digits stand for NaN `f`'s payload: its exponent field 0x3ff (pl-write.c)."
function NaN_value(f::Float64)::Float64
    u = reinterpret(UInt64, f)
    @assert (u >> 52) & 0x7ff == 0x7ff                  # NaN exponent
    return reinterpret(Float64, (u & ~(UInt64(0x7ff) << 52)) | (UInt64(0x3ff) << 52))
end

# PORT: pl-write.c make_nan
# DIVERGES: returns `(status, value)`, where upstream rewrites `*f`; the exponent field as in
# `NaN_value`.
"The NaN whose payload `f` writes (`1.5NaN`): `(NUM_OK, nan)`, or `(NUM_CONSTRANGE, f)` (pl-write.c)."
function make_nan(f::Float64)::Tuple{strnumstat, Float64}
    u = reinterpret(UInt64, f)
    d = reinterpret(Float64, u | (UInt64(0x7ff) << 52))  # NaN exponent
    isnan(d) && return (NUM_OK, d)
    return (NUM_CONSTRANGE, f)                          # 1.0NaN is in fact 1.0Inf
end

# ── quoting (pl-write.c) ────────────────────────────────────────────────────────────────────────

# PORT: pl-write.c AT_LOWER
"atomType(): an atom written as it is: a lowercase identifier (pl-write.c)."
const AT_LOWER = 0
# PORT: pl-write.c AT_QUOTE
"atomType(): an atom that must be quoted (pl-write.c)."
const AT_QUOTE = 1
# PORT: pl-write.c AT_FULLSTOP
"atomType(): the atom `.`, quoted (pl-write.c)."
const AT_FULLSTOP = 2
# PORT: pl-write.c AT_SYMBOL
"atomType(): an atom of symbol characters (pl-write.c)."
const AT_SYMBOL = 3
# PORT: pl-write.c AT_SOLO
"atomType(): a single solo character (pl-write.c)."
const AT_SOLO = 4
# PORT: pl-write.c AT_SPECIAL
"atomType(): `[]` or `{}` (pl-write.c)."
const AT_SPECIAL = 5

# The value C's `char` gives a Latin-1 character `c`: x86-64's `char` is signed, so 0x80-0xFF come
# out negative. Upstream reads a single-byte atom's or string's text as `char` in places
# (`atomType`'s `code_requires_quoted(*s, …)`, `writeText`'s `PutOpenToken(s[0], …)`); the kernel
# passes the same value there (docs/upstream_reports.md #11).
_signed_char(c::Int)::Int = c >= 0x80 ? c - 0x100 : c

# PORT: pl-write.c wr_is_symbol
# DIVERGES: the write options' flags, where upstream passes the options (NULL: no flags).
"Is `c` a symbol character for the writer with `flags` (pl-write.c)?"
wr_is_symbol(c::Int, flags::Int)::Bool =
    f_is_prolog_symbol(c) || (c == Int('`') && (flags & PL_WRT_BACKQUOTE_IS_SYMBOL) != 0)

# PORT: pl-write.c wr_is_solo
"May `c` be written as a bare single-character atom (pl-write.c)?"
function wr_is_solo(c::Int, flags::Int)::Bool
    f_is_prolog_solo(c) || return false
    (flags & PL_WRT_PATTERN_SYNTAX_SOLO) != 0 && return f_is_pattern_syntax(c)
    return true
end

# PORT: pl-write.c code_requires_quoted
"Must `c` be quoted when written to `fd` with `flags` (pl-write.c)?"
function code_requires_quoted(c::Int, fd::Union{Nothing, IOSTREAM}, flags::Int)::Bool
    c > 0x7f && (flags & PL_WRT_QUOTE_NON_ASCII) != 0 && return true
    fd !== nothing && Scanrepresent(c, fd) != 0 && return true
    return false
end

# PORT: pl-write.c text_has_combining
# DIVERGES: the text is a String, its characters taken in turn.
"Has the text a character of width 0 at or above U+0300 (a combining mark, a joiner…) (pl-write.c)?"
function text_has_combining(text::String)::Bool
    for ch in text
        c = Int(ch)
        c >= 0x300 && PL_wcwidth(c) == 0 && return true
    end
    return false
end

# PORT: pl-write.c atom_has_combining
# DIVERGES: the atom's text; a wide atom (`isUCSAtom`) is one with a character above 0xFF.
"Has the text atom with text `name` a combining character (pl-write.c)? A Latin-1 atom has none."
atom_has_combining(name::String)::Bool = _is_ucs_text(name) && text_has_combining(name)

# An atom or a string is held wide by upstream (`isUCSAtom`, ENC_WCHAR) when a character of its text
# is above 0xFF, and as ISO Latin-1 otherwise: upstream chooses the storage by that rule.
_is_ucs_text(text::String)::Bool = any(ch -> Int(ch) > 0xff, text)

# PORT: pl-write.c bracketPairAtom
# DIVERGES: returns `(found, open, close)`, where upstream writes them through pointers; the atom's
# text (`sym_text`), a reserved symbol having none (`get_atom_text`). KNOWN UPSTREAM DEFECT, ported
# AS IS (docs/upstream_reports.md #12): the pair need not be above ASCII, so `'[]'(a)` is written
# `[a]` and `'()'(a)` `(a)` — texts that read back as another term.
"Is `a` a bracket-pair atom `'<open><close>'`, and which are its brackets (pl-write.c)?"
function bracketPairAtom(a::T)::Tuple{Bool, Int, Int} where {T}
    isTextAtom(a) || return (false, 0, 0)
    s = sym_text(a)
    length(s) == 2 || return (false, 0, 0)
    c0 = Int(s[1])
    c1 = Int(s[nextind(s, 1)])
    cl = f_paren_close(c0)
    if cl != -1 && cl == c1
        return (true, c0, cl)
    end
    return (false, 0, 0)
end

# PORT: pl-write.c atomType
# DIVERGES: the single-byte atom's text (`sym_text`), the stream and the flags of the write options
# (`nothing` and 0 for upstream's NULL options); no `var_prefix` (the module flag is not ported,
# so it is off) and `dot_in_atom` off (SWI-7's default); `[]` is a reserved symbol (`ATOM_nil`,
# written by `writeReservedSymbol`), so only `{}` is `AT_SPECIAL` by its text. KNOWN UPSTREAM
# DEFECT, ported AS IS (docs/upstream_reports.md #11): a character after the first goes to
# `code_requires_quoted` as C's signed `char` (`_signed_char`), and the first is never tested, so
# `quote_non_ascii(true)` — write_canonical/1's — leaves a Latin-1 atom (`aé`) unquoted.
"How the single-byte atom with text `name` must be written to `fd` with `flags` (pl-write.c `AT_*`)."
function atomType(name::String, fd::Union{Nothing, IOSTREAM}, flags::Int)::Int
    n = length(name)
    n == 0 && return AT_QUOTE
    c0 = Int(name[1])
    if f_is_prolog_atom_start(c0)
        k = nextind(name, 1)
        left = n - 1
        while left > 0
            c = Int(name[k])
            (
                f_is_prolog_identifier_continue(c) &&
                !code_requires_quoted(_signed_char(c), fd, flags)
            ) || break
            k = nextind(name, k)
            left -= 1
        end
        return left == 0 ? AT_LOWER : AT_QUOTE
    end
    if wr_is_symbol(_signed_char(c0), flags)
        n == 1 && c0 == Int('.') && return AT_FULLSTOP
        n >= 2 && c0 == Int('/') && name[nextind(name, 1)] == '*' && return AT_QUOTE
        for ch in name
            c = _signed_char(Int(ch))
            (wr_is_symbol(c, flags) && !code_requires_quoted(c, fd, flags)) ||
                return AT_QUOTE
        end
        return AT_SYMBOL
    end
    if n == 1 && c0 != Int('%')                     # % should be quoted!
        wr_is_solo(c0, flags) && return AT_SOLO
    end
    # a == ATOM_nil || a == ATOM_curl: ATOM_nil is SWI-7's `[]`, a reserved symbol, never the
    # text atom `'[]'` (written quoted: probed), so only `{}` is AT_SPECIAL by its text
    name == "{}" && return AT_SPECIAL
    return AT_QUOTE
end

"`atomType` with upstream's NULL options: no stream, no flags (as `unquoted_atom` asks)."
atomType(name::String)::Int = atomType(name, nothing, 0)

# PORT: pl-write.c unquoted_text
# DIVERGES: the text is a String, its characters taken in turn (`text_next_char`); `dot_in_atom`
# off (SWI-7's default).
"May the text be written to `fd` with `flags` as an atom without quotes (pl-write.c)?"
function unquoted_text(text::String, fd::Union{Nothing, IOSTREAM}, flags::Int)::Bool
    isempty(text) && return false
    c = Int(text[1])
    i2 = nextind(text, 1)
    if i2 > ncodeunits(text)                        # single character atom
        wr_is_solo(c, flags) && return true
    elseif c >= 0x80                                # '<open><close>' prints like {}
        c2 = Int(text[i2])
        nextind(text, i2) > ncodeunits(text) && f_paren_close(c) == c2 && return true
    end
    if !f_is_prolog_atom_start(c)                   # Sequence of symbol chars
        for ch in text
            (f_is_prolog_symbol(Int(ch)) && !code_requires_quoted(Int(ch), fd, flags)) ||
                return false
        end
        return true
    end
    code_requires_quoted(c, fd, flags) && return false
    k = i2                                          # 1st char is ID_START
    while k <= ncodeunits(text)
        ch = Int(text[k])
        (f_is_prolog_identifier_continue(ch) && !code_requires_quoted(ch, fd, flags)) ||
            return false
        k = nextind(text, k)
    end
    return true
end

# PORT: pl-write.c unquoted_atomW
"May the wide atom with text `name` be written to `fd` with `flags` without quotes (pl-write.c)?"
unquoted_atomW(name::String, fd::Union{Nothing, IOSTREAM}, flags::Int)::Bool =
    unquoted_text(name, fd, flags)

# PORT: pl-write.c unquoted_atom
# DIVERGES: an atom is a wide (`isUCSAtom`) one when its text has a character above 0xFF, where
# upstream asks the atom's storage — which upstream chooses by the same rule; a reserved symbol
# (`[]`) is not a text atom (`PL_BLOB_TEXT`).
"May the text atom `a` be written without quotes (pl-write.c)?"
function unquoted_atom(a::T)::Bool where {T}
    is_reserved_symbol(a) && return false
    name = sym_text(a)
    _is_ucs_text(name) && return unquoted_atomW(name, nothing, 0)
    return atomType(name) != AT_QUOTE
end

# PORT: pl-write.c atomIsVarName
# DIVERGES: the atom's text, a String.
"Is `name` a variable name for the var_prefix `prefix` (0: none) (pl-write.c)?"
function atomIsVarName(name::String, prefix::Int)::Bool
    isempty(name) && return false
    c0 = Int(name[1])
    if prefix != 0
        (c0 != prefix || (prefix != Int('_') && length(name) == 1)) && return false
    elseif !f_is_prolog_var_start(c0)
        return false
    end
    k = nextind(name, 1)
    while k <= ncodeunits(name)
        f_is_prolog_identifier_continue(Int(name[k])) || return false
        k = nextind(name, k)
    end
    return true
end

# PORT: pl-write.c atomIsAnyVarName
"Is `name` a variable name for some var_prefix (pl-write.c)?"
function atomIsAnyVarName(name::String)::Bool
    atomIsVarName(name, 0) && return true
    if length(name) > 1
        c0 = Int(name[1])
        return c0 < 0x80 && f_is_prolog_symbol(c0) && atomIsVarName(name, c0)
    end
    return false
end

# ── the options and the frames (pl-write.c) ─────────────────────────────────────────────────────

# PORT: pl-write.c W_OP_ARG
"writeTerm()'s location of a term: an operator's argument (pl-write.c)."
const W_OP_ARG = 1
# PORT: pl-write.c W_TOP
"writeTerm()'s location of a term: the top term (pl-write.c)."
const W_TOP = 0
# PORT: pl-write.c W_LIST_ARG
"writeTerm()'s location of a term: a list element (pl-write.c)."
const W_LIST_ARG = 0
# PORT: pl-write.c W_LIST_TAIL
"writeTerm()'s location of a term: a list's tail, behind `|` (pl-write.c)."
const W_LIST_TAIL = 0
# PORT: pl-write.c W_COMPOUND_ARG
"writeTerm()'s location of a term: `f(arg)` (pl-write.c)."
const W_COMPOUND_ARG = 0
# PORT: pl-write.c W_BLOCK_OP
"writeTerm()'s location of a term: the block of a `{}` or `[]` block operator (pl-write.c)."
const W_BLOCK_OP = 0
# PORT: pl-write.c W_PREFIX_ARG
"writeTerm()'s location of a term: `f arg` (pl-write.c)."
const W_PREFIX_ARG = W_OP_ARG
# PORT: pl-write.c W_POSTFIX_ARG
"writeTerm()'s location of a term: `arg f` (pl-write.c)."
const W_POSTFIX_ARG = W_OP_ARG
# PORT: pl-write.c W_INFIX_ARG1
"writeTerm()'s location of a term: `arg1 f arg2`'s left argument (pl-write.c)."
const W_INFIX_ARG1 = W_OP_ARG
# PORT: pl-write.c W_INFIX_ARG2
"writeTerm()'s location of a term: `arg1 f arg2`'s right argument (pl-write.c)."
const W_INFIX_ARG2 = W_OP_ARG

# PORT: pl-write.c wf_kind
"What remains of a level of `writeTerm` when its subterm is written (pl-write.c)."
@enum wf_kind begin
    WF_LEAF = 0             # no continuation
    WF_BRACE                # {Term}: the closing `}'
    WF_BRACKET              # «Term»: the closing bracket
    WF_LIST_ELEM            # [...]: after an element
    WF_LIST_TAIL            # [...|Tail]: after the tail
    WF_DOT_HEAD             # '[|]'(H,T): after H
    WF_DOT_TAIL             # '[|]'(H,T): after T
    WF_DICT_TAG             # Tag{...}: after Tag
    WF_DICT_KEY             # after a key
    WF_DICT_VALUE           # after a value
    WF_PREFIX_BLOCK         # after the block of a prefix op
    WF_PREFIX_ARG           # after the arg of a prefix op
    WF_POSTFIX_ARG          # after the arg of a postfix op
    WF_POSTFIX_BLOCK        # after the block of a postfix op
    WF_INFIX_ARG1           # after the left arg of an infix op
    WF_INFIX_BLOCK          # after the block of an infix op
    WF_INFIX_ARG2           # after the right arg of an infix op
    WF_CANON_ARG            # f(...): after an argument
end

# PORT: pl-write.c WF_SUB
"writeTerm2()'s return: write the subterm in `sub` (pl-write.c)."
const WF_SUB = 2

# PORT: pl-write.c wsub
# DIVERGES: the subterm itself, where upstream holds a term reference (see `wframe`).
"The subterm `writeTerm` writes next (pl-write.c)."
mutable struct wsub{T}
    t::T
    prec::Int
    flags::Int
end

# PORT: pl-write.c wframe
# DIVERGES: a level holds its terms themselves (`t`, `arg`, the list's `list` and `head`), where
# upstream holds term references in a foreign frame of the level (`fid`), which it closes when the
# level is done: no garbage collector moves a kernel term, so nothing needs the references. A
# compound whose head is no symbol (the kernel's `$expr/n`) is written as `'$expr'` with every child
# an argument: `off` is where the arguments start among its children (1: after a symbol head; 0).
# NOT PORTED: the dict fields (`u.dict`: the kernel has no dicts).
"A level of `writeTerm`: what remains to be written when its subterm is done (pl-write.c)."
mutable struct wframe{T}
    depth::Int                      # options->depth to restore
    t::T                            # the term being written
    arg::T                          # work reference of the level
    functor::T
    arity::Int
    off::Int                        # (the children before the first argument)
    n::Int                          # argument or pair index
    op_pri::Int
    op_type::UInt8
    kind::wf_kind
    embrace::Bool                   # emit the closing brace
    bclose::Int                     # WF_BRACKET: closing bracket
    list::T                         # WF_LIST_*, WF_DOT_*: remainder of the list
    head::T
    parens::Int                     # WF_DOT_*: parens to close
end

wframe{T}(z::T) where {T} =
    wframe{T}(0, z, z, z, 0, 1, 0, 0, 0x00, WF_LEAF, false, 0, z, z, 0)

# PORT: pl-write.c write_options
# DIVERGES: the writer's database (`gd`: the operator table, `user:portray/1`) and local data (`ld`:
# a term is dereferenced through its bindings) are fields, where upstream reaches them through
# `GET_LD`; `integer_format` and `float_format` are texts and `spacing` a Symbol (`:standard`,
# `:next_argument`), where upstream holds atoms. The text atoms the writer compares a functor with
# (upstream's `ATOM_*`) are their keys, made once per write (`k_*`); `writeTerm`'s stack (upstream's
# segstack, a local of each call) is a field, so a write allocates it once. NOT PORTED:
# `portray_goal`, `write_options` and `prec_opt` (write_term/2,3's `portray_goal` option, R1e).
"The options of a write (pl-write.c)."
mutable struct write_options{T}
    flags::Int                      # PL_WRT_* flags
    max_depth::Int                  # depth limit
    depth::Int                      # current depth
    max_text::Int                   # Limit length for atoms/strings
    truncated::Bool                 # max_depth was exceeded
    integer_format::String          # How to format integers
    float_format::String            # How to format floats
    spacing::Symbol                 # Where to insert spaces
    m::module_t{T}                  # Module for operators (upstream's `module`, a keyword here)
    out::IOSTREAM                   # stream to write to
    gd::PL_global_data{T}
    ld::PL_local_data{T}
    frames::Vector{wframe{T}}       # (writeTerm's stack)
    sub::wsub{T}                    # (writeTerm's subterm)
    k_curl::UInt64                  # ATOM_curl, '{}'
    k_dot::UInt64                   # ATOM_dot, '[|]'
    k_comma::UInt64                 # ATOM_comma
    k_bar::UInt64                   # ATOM_bar
    k_minus::UInt64                 # ATOM_minus
    k_fdot::UInt64                  # '.'
    k_divide::UInt64                # ATOM_divide
    k_isovar::UInt64                # FUNCTOR_isovar1's name, '$VAR'
end

# PORT: pl-write.c WRITE_OPTIONS_DEFAULTS as write_options
# DIVERGES: a constructor, given what upstream's callers set after it: the stream, and the module
# (`user`); the database and local data (see `write_options`).
"Write options with upstream's defaults, writing to `out` (pl-write.c `WRITE_OPTIONS_DEFAULTS`)."
function write_options(
    gd::PL_global_data{T}, ld::PL_local_data{T}, out::IOSTREAM
)::write_options{T} where {T}
    z = mk_nil(T)
    return write_options{T}(
        0, 0, 0, -1, false, "~d", "~h", :standard, MODULE_user(gd), out, gd, ld,
        wframe{T}[], wsub{T}(z, 0, 0),
        sym_key(mk_sym(T, Symbol("{}"))), sym_key(mk_sym(T, Symbol("[|]"))),
        sym_key(mk_sym(T, Symbol(","))), sym_key(mk_sym(T, Symbol("|"))),
        sym_key(mk_sym(T, Symbol("-"))), sym_key(mk_sym(T, Symbol("."))),
        sym_key(mk_sym(T, Symbol("/"))), sym_key(mk_sym(T, Symbol("\$VAR")))
    )
end

# Is a flag of `mask` set in the write options (upstream's `ison(options, mask)`)?
_ison(options::write_options, mask::Int)::Bool = (options.flags & mask) != 0

# Is `a` the text atom whose key is `k` (upstream compares atom handles: `functor == ATOM_…`)?
_is_text_atom_key(a::T, k::UInt64) where {T} = kind(a) === SYM && sym_key(a) == k

# PORT: pl-write.c out_var_prefix
# DIVERGES: always 0 — the module's `var_prefix` flag is not ported (no `var_prefix/1`).
"The var_prefix character of the write's module, 0 for none (pl-write.c)."
out_var_prefix(options::write_options)::Int = 0

# ── primitive writes (pl-write.c) ───────────────────────────────────────────────────────────────
# The token layer takes the stream and the flags of the write options, where upstream takes the
# options: what it reads of them (`out`, `flags`, and the module's `var_prefix`, which is not
# ported). Upstream's own callers that pass options with only a stream (`{.out = s}`:
# `separate_number`, `writeReservedSymbol`) pass flags 0.

# PORT: pl-write.c TRUE_WITH_SPACE
"OK, and a space was emitted before the token (pl-write.c)."
const TRUE_WITH_SPACE = 2

# PORT: pl-write.c Putc
"Write character `c` to `s` (pl-write.c)."
Putc(c::Int, s::IOSTREAM)::Bool = Sputcode(c, s) != EOF

# PORT: pl-write.c PutString
# DIVERGES: the String's bytes, each written as a character (upstream's `unsigned char` loop): its
# callers pass ASCII.
"Write the bytes of `str` to `s` (pl-write.c)."
function PutString(str::String, s::IOSTREAM)::Bool
    for b in codeunits(str)
        Sputcode(Int(b), s) == EOF && return false
    end
    return true
end

# PORT: pl-write.c PutComma
"Write the comma between arguments, with a space for `spacing(next_argument)` (pl-write.c)."
PutComma(options::write_options)::Bool =
    if options.spacing === :next_argument
        PutString(", ", options.out)
    else
        PutString(",", options.out)
    end

# PORT: pl-write.c PutBar
"Write the bar of a list's tail, with a space for `spacing(next_argument)` (pl-write.c)."
PutBar(options::write_options)::Bool =
    if options.spacing === :next_argument
        PutString("| ", options.out)
    else
        PutString("|", options.out)
    end

# PORT: pl-write.c C_PREFIX_SIGN
"`lastc` flag: `-` as a prefix operator (pl-write.c)."
const C_PREFIX_SIGN = 0x00200000
# PORT: pl-write.c C_PREFIX_OP
"`lastc` flag: any prefix operator (pl-write.c)."
const C_PREFIX_OP = 0x00400000
# PORT: pl-write.c C_INFIX_OP
"`lastc` flag: any infix operator (pl-write.c)."
const C_INFIX_OP = 0x00800000
# PORT: pl-write.c C_MASK
"The `lastc` flags' bits (pl-write.c)."
const C_MASK = 0xffe00000

# PORT: pl-write.c isquote
"Is `c` a quote character for a write with `flags` (pl-write.c)?"
function isquote(c::Int, flags::Int)::Bool
    c == Int('"') && return true
    c == Int('\'') && return true
    c == Int('`') && (flags & PL_WRT_BACKQUOTE_IS_SYMBOL) == 0 && return true
    return false
end

# PORT: pl-write.c needSpace
"Must a space go between the last character written to `s` and `c` to keep them two tokens (pl-write.c)?"
function needSpace(c::Int, s::IOSTREAM, flags::Int)::Bool
    if c == EOF
        s.lastc = EOF
        return false
    end
    s.lastc == EOF && return false

    if (s.lastc & C_PREFIX_SIGN) != 0 && (isDigit(c) || f_is_prolog_symbol(c))
        return true
    end
    if (s.lastc & C_PREFIX_OP) != 0 &&
        (c == Int('(') || c == Int('{') ||          # avoid op(...)
        f_is_prolog_symbol(c))                     # avoid not-a: reads as the prefix op, looks infix
        return true
    end
    (s.lastc & C_INFIX_OP) != 0 && c == Int('(') && return false

    s.lastc &= Int(~UInt32(C_MASK))

    # prefix = out_var_prefix(options): always 0, so `?(a,x) -> a?x` cannot arise

    lastc = s.lastc
    if (f_is_prolog_identifier_continue(lastc) && f_is_prolog_identifier_continue(c)) ||
        (f_is_prolog_symbol(lastc) && f_is_prolog_symbol(c)) ||
        (c == Int('(') && !(isPunctW(lastc) || isBlank(lastc))) ||
        (c == Int('\'') && isDigit(lastc)) ||
        (isquote(c, flags) && lastc == c)
        return true
    end

    return false
end

# PORT: pl-write.c PutOpenToken
"Write a space if `c` would join the last token written to `s`: 0 (error), 1, or `TRUE_WITH_SPACE` (pl-write.c)."
function PutOpenToken(c::Int, s::IOSTREAM, flags::Int)::Int
    if needSpace(c, s, flags)
        Putc(Int(' '), s) || return 0
        return TRUE_WITH_SPACE
    end
    return 1
end

# PORT: pl-write.c PutToken
"Write the token `str` (ASCII) to `s`, a space before it where needed: 0, 1, or `TRUE_WITH_SPACE` (pl-write.c)."
function PutToken(str::String, s::IOSTREAM, flags::Int)::Int
    if !isempty(str)
        rc = PutOpenToken(Int(codeunit(str, 1)), s, flags)
        rc == 0 && return 0
        PutString(str, s) || return 0
        return rc
    end
    return 1
end

# PORT: pl-write.c PutVarName
# DIVERGES: no var_prefix (`out_var_prefix` is 0), so no `PutVarPrefix` before the name.
"Write the name of an unbound variable, `_123` (pl-write.c)."
PutVarName(name::String, options::write_options)::Bool =
    PutToken(name, options.out, options.flags) != 0

# PORT: pl-write.c PutElipsis
"Write `…` (`...` where the stream cannot represent it), a space before it if `first` (pl-write.c)."
function PutElipsis(first::Bool, options::write_options)::Bool
    rc = 1
    out = options.out
    if Scanrepresent(Int(0x2026), out) == 0
        if first
            rc = PutOpenToken(Int(0x2026), out, options.flags)
            rc == 0 && return false
        end
        Sputcode(Int(0x2026), out) == -1 && return false
        return rc != 0
    else
        if first
            rc = PutOpenToken(Int('.'), out, options.flags)
            rc == 0 && return false
        end
        PutString("...", out) || return false
        return rc != 0
    end
end

# PORT: pl-write.c PutOpenBrace
"Write `(` around a term, a space before it where needed: 0, 1, or `TRUE_WITH_SPACE` (pl-write.c)."
function PutOpenBrace(options::write_options)::Int
    rc = PutOpenToken(Int('('), options.out, options.flags)
    rc == 0 && return 0
    Putc(Int('('), options.out) || return 0
    return rc
end

# PORT: pl-write.c PutCloseBrace
"Write `)` (pl-write.c)."
PutCloseBrace(s::IOSTREAM)::Bool = Putc(Int(')'), s)

# PORT: pl-write.c unicode_quoted_escape
"Must `c` be escaped in a quoted atom or string: its width is undefined (pl-write.c)?"
unicode_quoted_escape(c::Int)::Bool = PL_wcwidth(c) < 0

# PORT: pl-write.c putQuoted
"Write `c` inside a text quoted by `quote`: the number of characters written, or -1 (pl-write.c)."
function putQuoted(c::Int, qc::Int, flags::Int, stream::IOSTREAM)::Int
    if (flags & PL_WRT_CHARESCAPES) != 0
        if !unicode_quoted_escape(c) && c != qc && c != Int('\\') &&
            Scanrepresent(c, stream) == 0
            Putc(c, stream) || return -1
        else
            esc = if c == qc
                string(Char(c))
            elseif c == 7
                "a"
            elseif c == Int('\b')
                "b"
            elseif c == Int('\t')
                "t"
            elseif c == Int('\n')
                "n"
            elseif c == 11
                "v"
            elseif c == Int('\r')
                "r"
            elseif c == Int('\f')
                "f"
            elseif c == Int('\\')
                "\\"
            elseif (flags & PL_WRT_CHARESCAPES_UNICODE) != 0
                # `%04X`, `%08X` of an `int`: a negative one is its two's complement
                h = uppercase(string(c % UInt32; base=16))
                c <= 0xffff ? "u" * lpad(h, 4, '0') : "U" * lpad(h, 8, '0')
            else
                "x" * uppercase(string(c % UInt32; base=16)) * "\\"
            end
            (Putc(Int('\\'), stream) && PutString(esc, stream)) || return -1
            return 1 + ncodeunits(esc)              # `esc` is ASCII
        end
    else
        Putc(c, stream) || return -1
        if c == qc                               # write ''
            Putc(c, stream) || return -1
            return 2
        end
    end
    return 1
end

# ── atoms, strings and numbers (pl-write.c) ─────────────────────────────────────────────────────

# PORT: pl-write.c write_chars
# DIVERGES: the `n` characters of `cs` from index `from`, for both encodings (upstream's
# `write_chars` and `write_wchars`); written unquoted one by one (`PutStringN`, `PutWStringN`).
"Write `n` characters of `cs` from `from`, inside quotes `quote` (0: none) (pl-write.c)."
function write_chars(
    cs::Vector{Char}, from::Int, n::Int, qc::Int, options::write_options
)::Bool
    for i in from:(from + n - 1)
        if qc != 0
            putQuoted(Int(cs[i]), qc, options.flags, options.out) < 0 && return false
        else
            Putc(Int(cs[i]), options.out) || return false
        end
    end
    return true
end

# PORT: pl-write.c writeText
# DIVERGES: the text is a String, `wide` saying whether upstream holds it as ENC_WCHAR (see
# `_is_ucs_text`); a single-byte text's first character goes to `PutOpenToken` as C's signed `char`
# (`_signed_char`), as upstream's `s[0]` does — KNOWN UPSTREAM DEFECT, ported AS IS
# (docs/upstream_reports.md #11): an atom starting with a Latin-1 letter is not separated from a
# letter before it, so `dynamic é` is written `dynamicé`.
"Write `txt` inside quotes `quote` (0: none), cut to `max_text`: 0, 1, or `TRUE_WITH_SPACE` (pl-write.c)."
function writeText(txt::String, wide::Bool, qc::Int, options::write_options)::Int
    rc = 1
    len = length(txt)
    len == 0 && return 1
    out = options.out
    first = wide ? Int(txt[1]) : _signed_char(Int(txt[1]))

    if options.max_text >= 0
        if len > options.max_text
            mt = options.max_text
            sl = min(mt, mt ÷ 2)                    # suffix len
            pl = mt - sl                            # prefix len
            quoted_ellipsis = false
            cs = collect(txt)

            options.truncated = true

            if qc == 0 && _ison(options, PL_WRT_QUOTED)
                quoted_ellipsis = true
                qc = Int('\'')
                rc = PutOpenToken(qc, out, options.flags)
                (rc != 0 && Putc(qc, out)) || return 0
            end

            if pl > 0
                if qc == 0
                    rc = PutOpenToken(first, out, options.flags)
                    rc == 0 && return 0
                end
                write_chars(cs, 1, pl, qc, options) || return 0
                PutElipsis(false, options) || return 0
            else
                rc = PutElipsis(true, options) ? 1 : 0
                rc == 0 && return 0
            end
            write_chars(cs, len - sl + 1, sl, qc, options) || return 0
            if rc != 0 && quoted_ellipsis
                Putc(qc, out) || return 0
            end
            return rc
        end
    end

    if qc == 0
        rc = PutOpenToken(first, out, options.flags)
        rc == 0 && return 0
    end
    for ch in txt
        if qc != 0
            putQuoted(Int(ch), qc, options.flags, out) < 0 && return 0
        else
            Putc(Int(ch), out) || return 0
        end
    end
    return rc
end

# PORT: pl-write.c writeReservedSymbol
# DIVERGES: the symbol's name is its text (`sym_text`), each byte as C's signed `char`.
"Write the reserved symbol `atom`: `[]`, else `C'name'` when quoted (pl-write.c)."
function writeReservedSymbol(fd::IOSTREAM, atom::T, flags::Int)::Bool where {T}
    is_nil(atom) && return PutToken("[]", fd, 0) != 0

    bytes = codeunits(sym_text(atom))
    if (flags & PL_WRT_QUOTED) != 0
        qc = Int('\'')

        if PutOpenToken(Int('C'), fd, 0) != 0 && Putc(Int('C'), fd) && Putc(qc, fd)
            for b in bytes
                putQuoted(_signed_char(Int(b)), qc, flags, fd) < 0 && return false
            end
            return Putc(qc, fd)
        end
    end

    !isempty(bytes) && PutOpenToken(_signed_char(Int(bytes[1])), fd, 0) == 0 && return false
    for b in bytes
        Putc(_signed_char(Int(b)), fd) || return false
    end
    return true
end

# PORT: pl-write.c writeUCSAtom
# DIVERGES: the wide atom's text (the `write_ex` of upstream's `ucs_atom` blob type).
"Write the wide atom with text `name`, quoted where `quoted(true)` needs it (pl-write.c)."
function writeUCSAtom(name::String, options::write_options)::Bool
    if _ison(options, PL_WRT_QUOTED) &&
        (!unquoted_atomW(name, options.out, options.flags) || atom_has_combining(name))
        qc = Int('\'')

        return PutOpenToken(qc, options.out, options.flags) != 0 &&
               Putc(qc, options.out) &&
               writeText(name, true, qc, options) != 0 &&
               Putc(qc, options.out)
    else
        return writeText(name, true, 0, options) != 0
    end
end

# PORT: pl-write.c writeAtom
# DIVERGES: an atom is a symbol: a reserved symbol is written by its blob type's `write`
# (`writeReservedSymbol`), a wide text atom by its `write_ex` (`writeUCSAtom`), a single-byte one
# here — so, as upstream, only the last can return `TRUE_WITH_SPACE`. No released blobs, no other
# blob types. NOT PORTED: `PL_WRT_BLOB_PORTRAY` (write_term/2,3's `blobs(portray)`, R1e): refused
# (`NotPortedError`) where it would call portray/1.
"Write the atom `a`: 0, 1, or `TRUE_WITH_SPACE` (pl-write.c)."
function writeAtom(a::T, options::write_options{T})::Int where {T}
    if _ison(options, PL_WRT_BLOB_PORTRAY) && is_reserved_symbol(a) && !is_nil(a)
        throw(
            NotPortedError{T}(
                a, "writing a blob with portray/1 (blobs(portray))", "R1e (write_term/2,3)"
            )
        )
    end

    if is_reserved_symbol(a)                        # atom->type->write
        return if (
            writeReservedSymbol(options.out, a, options.flags) && Sferror(options.out) == 0
        )
            1
        else
            0
        end
    end
    text = sym_text(a)
    if _is_ucs_text(text)                           # atom->type->write_ex
        return (writeUCSAtom(text, options) && Sferror(options.out) == 0) ? 1 : 0
    end

    if _ison(options, PL_WRT_QUOTED)
        t = atomType(text, options.out, options.flags)
        # `atom_has_combining`: a single-byte atom has no combining character
        if t == AT_LOWER || t == AT_SYMBOL || t == AT_SOLO || t == AT_SPECIAL
            return writeText(text, false, 0, options)
        else                                        # AT_QUOTE, AT_FULLSTOP
            qc = Int('\'')

            rc = PutOpenToken(qc, options.out, options.flags)
            (
                rc != 0 && Putc(qc, options.out) &&
                writeText(text, false, qc, options) != 0 &&
                Putc(qc, options.out)
            ) || return 0

            return rc
        end
    else
        return writeText(text, false, 0, options)
    end
end

# PORT: pl-write.c writeString
# DIVERGES: the string's text (`string_value`), where upstream asks `PL_get_text`.
"Write the string `t`: quoted with `\"` (`` ` `` for `back_quotes(string)`) when `quoted(true)` (pl-write.c)."
function writeString(t::T, options::write_options{T})::Bool where {T}
    txt = string_value(t)
    wide = _is_ucs_text(txt)

    if _ison(options, PL_WRT_QUOTED)
        qc = _ison(options, PL_WRT_BACKQUOTED_STRING) ? Int('`') : Int('"')

        return PutOpenToken(qc, options.out, options.flags) != 0 &&
               Putc(qc, options.out) &&
               writeText(txt, wide, qc, options) != 0 &&
               Putc(qc, options.out)
    else
        return writeText(txt, wide, 0, options) != 0
    end
end

# PORT: pl-write.c writeMPZ
# DIVERGES: a Julia `BigInt` (an `Integer`), its decimal digits by `string`, where upstream asks GMP.
"Write the integer `mpz` in decimal as a token (pl-write.c)."
writeMPZ(mpz::Integer, options::write_options)::Bool =
    PutToken(string(mpz), options.out, options.flags) != 0

# PORT: pl-write.c separate_number
# DIVERGES: the number's sign, where upstream passes the number (`ar_signbit`), and the format's
# text; options with only the stream, as upstream's.
"Write a space before a number to `s` where its first character would join the last token (pl-write.c)."
function separate_number(s::IOSTREAM, negative::Bool, fmt::String)::Bool
    c = isempty(fmt) ? -1 : Int(fmt[1])

    if !(c >= 0 && c != Int('~'))
        c = negative ? Int('-') : Int('0')
    end

    needSpace(c, s, 0) && return Putc(Int(' '), s)

    return true
end

# PORT: pl-write.c writeNumber
# DIVERGES: an integer is written as `do_format` writes it with the default format `~d`, the only
# one before write_term/2,3's `integer_format` option (R1e): its decimal digits. NOT PORTED: a
# float (`format_float`, `~h`: R1e) — refused (`NotPortedError`).
"Write the number `t` (pl-write.c): an integer, or a rational as `NrD` (`N/D` for `RAT_NATURAL`)."
function writeNumber(t::T, options::write_options{T})::Bool where {T}
    k = number_kind(t)
    if k === NUM_INTEGER
        options.integer_format == "~d" || throw(
            NotPortedError{T}(t, "integer_format other than ~d", "R1e (write_term/2,3)")
        )
        if integer_is_int64(t)
            v = int64_value(t)
            separate_number(options.out, v < 0, options.integer_format) || return false
            digits = string(v)
        else
            z = bigint_value(t)
            separate_number(options.out, z < 0, options.integer_format) || return false
            digits = string(z)
        end
        return PutString(digits, options.out)       # do_format(out, "~d", 1, t, module)
    elseif k === NUM_RATIONAL
        q = rational_value(t)                       # num/den
        sep = _ison(options, PL_WRT_RAT_NATURAL) ? Int('/') : Int('r')

        writeMPZ(numerator(q), options) || return false
        Sputcode(sep, options.out) == EOF && return false
        options.out.lastc = EOF
        return writeMPZ(denominator(q), options)
    end
    throw(NotPortedError{T}(t, "writing a float (format_float)", "R1e (floats)"))
end

# PORT: pl-write.c varName
# DIVERGES: `_` and the variable's key, where upstream's number is the variable's stack offset
# (`var_name_ptr`): the same shape, and no test compares the number (user, 2026-10-07).
"The name a variable is written by: `_<number>` (pl-write.c)."
varName(t)::String = "_" * string(var_key(t))

# PORT: pl-write.c writePrimitive
# DIVERGES: the term itself, dereferenced; no attributed variables (`writeAttVar`). A grounded
# value SWI has no type for (`NUM_OTHER`, kernel-only) has no text: refused (`NotPortedError`).
"Write the variable, atom, number or string `t` (pl-write.c)."
function writePrimitive(t::T, options::write_options{T})::Bool where {T}
    kind(t) === VAR && return PutVarName(varName(t), options)

    kind(t) === SYM && return writeAtom(t, options) != 0

    isNumber(t) && return writeNumber(t, options)

    isString(t) && return writeString(t, options)

    throw(NotPortedError{T}(t, "writing a grounded value SWI has no type for", "never"))
end

# PORT: pl-write.c writeNumberVar
# DIVERGES: the term itself, dereferenced; no `numbervars_frame` (write_canonical/1 and
# write_term/2,3's `variable_names`, R1e: an older `'$VAR'` term is then written as a term); no
# var_prefix (`out_var_prefix` is 0). The atom `quoted(false)` writes is written with the write's
# options, its flag cleared and restored, where upstream writes it with a copy (`o2`) — so
# `truncated` is restored too.
"Write `'\$VAR'(N)` as a variable name: 1 (written), 0 (not such a term), -1 (error) (pl-write.c)."
function writeNumberVar(t::T, options::write_options{T})::Int where {T}
    ld = options.ld
    kind(t) === EXPR || return 0
    (nchildren(t) == 2 && _is_text_atom_key(child(t, 1), options.k_isovar)) || return 0

    p = deRef(ld, child(t, 2))
    if isTaggedInt(p)
        n = int64_value(p)
        buf = if n < 0
            "S_" * string(-n)
        else
            i = Int(n % 26)
            j = n ÷ 26
            j == 0 ? string(Char(i + Int('A'))) : string(Char(i + Int('A'))) * string(j)
        end

        return PutToken(buf, options.out, options.flags) != 0 ? 1 : -1
    end

    if isTextAtom(p)
        name = sym_text(p)
        prefix = out_var_prefix(options)
        std = atomIsVarName(name, 0)
        plain = atomIsVarName(name, prefix) || (!std && atomIsAnyVarName(name))   # e.g. ?x

        if plain || (prefix != 0 && std)
            flags, truncated = options.flags, options.truncated
            options.flags &= ~PL_WRT_QUOTED
            rc = writeAtom(p, options)
            options.flags, options.truncated = flags, truncated

            return rc != 0 ? 1 : -1
        end
    end

    return 0
end

# ── portray (pl-write.c) ────────────────────────────────────────────────────────────────────────

# PORT: pl-write.c callPortray
# DIVERGES: no `portray_goal` (write_term/2,3, R1e) and no halt state. Calling Prolog from the
# writer needs the meta-call (V9): so where upstream would call `user:portray/1` — it is DEFINED —
# the kernel refuses (`NotPortedError`; user, 2026-10-07, decision 3a); where it is not, upstream
# returns false at once, and so does the kernel.
"Call `user:portray/1` on `arg`: 1 (it wrote it), 0 (not defined, or it failed), -1 (error) (pl-write.c)."
function callPortray(arg::T, prec::Int, options::write_options{T})::Int where {T}
    gd = options.gd
    proc = isCurrentProcedure(sym_key(mk_sym(T, :portray)), 1, MODULE_user(gd))
    (proc === nothing || !_impl_any_defined(proc.definition)) && return 0

    throw(
        NotPortedError{T}(
            arg, "print/1 and portray(true) with user:portray/1 defined (calling Prolog)",
            "V9 (the meta-call)"
        )
    )
end

# PORT: pl-write.c isBlockOp
# DIVERGES: the term itself, dereferenced; returns only the verdict (upstream also leaves the first
# argument in `arg`, which its callers then overwrite).
"Is `t`, named `functor`, a block operator term: `[](List, …)` or `{}({…}, …)` (pl-write.c)?"
function isBlockOp(t::T, functor::T, options::write_options{T})::Bool where {T}
    if is_nil(functor) || _is_text_atom_key(functor, options.k_curl)
        arg = deRef(options.ld, child(t, 2))
        if (is_nil(functor) && is_pair(arg)) ||
            (
            _is_text_atom_key(functor, options.k_curl) && kind(arg) === EXPR &&
            nchildren(arg) == 2 && _is_text_atom_key(child(arg, 1), options.k_curl)
        )
            return true
        end
    end
    return false
end

# ── write a subterm (pl-write.c) ────────────────────────────────────────────────────────────────

# PORT: pl-write.c sub_term
"Ask `writeTerm` to write `t` next and resume the level `f` as `kind` after it: `WF_SUB` (pl-write.c)."
function sub_term(
    f::wframe{T}, kind::wf_kind, sub::wsub{T}, t::T, prec::Int, flags::Int
)::Int where {T}
    f.kind = kind
    sub.t = t
    sub.prec = prec
    sub.flags = flags

    return WF_SUB
end

# The argument `i` of the compound a level writes: the child after the head, or the child itself
# for a compound with no symbol head (`$expr/n`, see `wframe`).
_wr_arg(f::wframe{T}, i::Int) where {T} = child(f.t, i + f.off)

# ── lists (pl-write.c) ──────────────────────────────────────────────────────────────────────────

# PORT: pl-write.c writeDotListHead
"Write `'[|]'(` (`.(` for `dotlists(true)`) and ask for the head of the list cell (pl-write.c)."
function writeDotListHead(
    options::write_options{T}, f::wframe{T}, sub::wsub{T}
)::Int where {T}
    l = deRef(options.ld, f.list)                   # PL_get_list(l, head, l)
    f.head = child(l, 2)
    f.list = child(l, 3)
    if _ison(options, PL_WRT_DOTLISTS)
        PutToken(".", options.out, options.flags) != 0 || return 0
    else
        writeAtom(mk_sym(T, Symbol("[|]")), options) != 0 || return 0   # ATOM_dot
    end

    Putc(Int('('), options.out) || return 0

    return sub_term(f, WF_DOT_HEAD, sub, f.head, 999, W_COMPOUND_ARG)
end

# PORT: pl-write.c writeListStart
"Start the list `list`: `[` and its first element, or the dotted notation (pl-write.c)."
function writeListStart(
    list::T, options::write_options{T}, f::wframe{T}, sub::wsub{T}
)::Int where {T}
    f.list = list
    f.parens = 0

    if (options.flags & (PL_WRT_DOTLISTS | PL_WRT_NO_LISTS)) == 0
        Putc(Int('['), options.out) || return 0
        l = deRef(options.ld, f.list)               # PL_get_list(l, head, l)
        f.head = child(l, 2)
        f.list = child(l, 3)

        return sub_term(f, WF_LIST_ELEM, sub, f.head, 999, W_LIST_ARG)
    end

    return writeDotListHead(options, f, sub)
end

# PORT: pl-write.c writeListElemDone
"After a list element: `]`, `|Tail`, or `,` and the next element (pl-write.c)."
function writeListElemDone(
    options::write_options{T}, f::wframe{T}, sub::wsub{T}
)::Int where {T}
    l = deRef(options.ld, f.list)

    is_nil(l) && return Putc(Int(']'), options.out) ? 1 : 0

    options.depth += 1
    if options.depth >= options.max_depth && options.max_depth != 0
        options.truncated = true
        return if (
            Putc(Int('|'), options.out) && PutElipsis(false, options) &&
            Putc(Int(']'), options.out)
        )
            1
        else
            0
        end
    end

    if !is_pair(l)
        Putc(Int('|'), options.out) || return 0

        return sub_term(f, WF_LIST_TAIL, sub, l, 999, W_LIST_TAIL)
    end

    PutComma(options) || return 0
    f.head = child(l, 2)
    f.list = child(l, 3)

    return sub_term(f, WF_LIST_ELEM, sub, f.head, 999, W_LIST_ARG)
end

# PORT: pl-write.c writeCloseParens
"Close the dotted notation's parentheses (pl-write.c)."
function writeCloseParens(options::write_options, f::wframe)::Bool
    parens = f.parens

    while parens > 0
        parens -= 1
        Putc(Int(')'), options.out) || return false
    end

    return true
end

# PORT: pl-write.c writeDotHeadDone
"After the head of a dotted list cell: `,` and the tail (pl-write.c)."
function writeDotHeadDone(
    options::write_options{T}, f::wframe{T}, sub::wsub{T}
)::Int where {T}
    l = deRef(options.ld, f.list)

    PutComma(options) || return 0
    f.parens += 1

    if is_nil(l)
        PutToken("[]", options.out, options.flags) != 0 || return 0

        return writeCloseParens(options, f) ? 1 : 0
    end

    options.depth += 1
    if options.depth >= options.max_depth && options.max_depth != 0
        options.truncated = true
        PutElipsis(true, options) || return 0

        return writeCloseParens(options, f) ? 1 : 0
    end

    is_pair(l) || return sub_term(f, WF_DOT_TAIL, sub, l, 999, W_COMPOUND_ARG)

    return writeDotListHead(options, f, sub)
end

# ── operators (pl-write.c) ──────────────────────────────────────────────────────────────────────

# PORT: pl-write.c writePrefixArg
"Ask for the argument of a prefix operator (pl-write.c)."
function writePrefixArg(
    options::write_options{T}, f::wframe{T}, sub::wsub{T}
)::Int where {T}
    # +/-(Number) : avoid parsing as number
    options.out.lastc |= C_PREFIX_OP
    if _is_text_atom_key(f.functor, options.k_minus)
        options.out.lastc |= C_PREFIX_SIGN
    end

    f.arg = _wr_arg(f, f.arity)

    return sub_term(
        f, WF_PREFIX_ARG, sub, f.arg, f.op_type == OP_FX ? f.op_pri - 1 : f.op_pri,
        W_PREFIX_ARG
    )
end

# PORT: pl-write.c writePostfixOp
"After the argument of a postfix operator: the operator, or ask for its block (pl-write.c)."
function writePostfixOp(
    options::write_options{T}, f::wframe{T}, sub::wsub{T}
)::Int where {T}
    if f.arity == 1
        writeAtom(f.functor, options) != 0 || return 0
    else
        if _is_text_atom_key(f.functor, options.k_curl)
            a = deRef(options.ld, f.arg)
            if isTextAtom(a) || kind(a) === VAR      # PL_is_atom || PL_is_variable
                Putc(Int(' '), options.out) || return 0
            end
        end
        f.arg = _wr_arg(f, 1)

        return sub_term(f, WF_POSTFIX_BLOCK, sub, f.arg, 1200, W_BLOCK_OP)
    end

    return f.embrace ? (PutCloseBrace(options.out) ? 1 : 0) : 1
end

# PORT: pl-write.c writeInfixArg2
"Ask for the right argument of an infix operator (pl-write.c)."
function writeInfixArg2(
    options::write_options{T}, f::wframe{T}, sub::wsub{T}
)::Int where {T}
    f.arg = _wr_arg(f, f.arity)

    return sub_term(
        f, WF_INFIX_ARG2, sub, f.arg,
        f.op_type == OP_XFX || f.op_type == OP_YFX ? f.op_pri - 1 : f.op_pri, W_INFIX_ARG2
    )
end

# PORT: pl-write.c writeInfixOp
"After the left argument of an infix operator: the operator, or ask for its block (pl-write.c)."
function writeInfixOp(options::write_options{T}, f::wframe{T}, sub::wsub{T})::Int where {T}
    out = options.out

    if f.arity == 2
        if _is_text_atom_key(f.functor, options.k_comma)
            PutComma(options) || return 0
        elseif _is_text_atom_key(f.functor, options.k_bar)
            PutBar(options) || return 0
        elseif _is_text_atom_key(f.functor, options.k_fdot)
            PutToken(".", out, options.flags) != 0 || return 0
        elseif _is_text_atom_key(f.functor, options.k_divide) &&
            _ison(options, PL_WRT_RAT_NATURAL) &&
            isInteger(deRef(options.ld, f.arg)) &&
            (f.arg=_wr_arg(f, 1); true) &&
            isNumber(deRef(options.ld, f.arg))
            PutString(" / ", out) || return 0
        else
            rc = writeAtom(f.functor, options)
            rc == 0 && return 0
            if rc == TRUE_WITH_SPACE
                Putc(Int(' '), out) || return 0
            end
        end
        out.lastc |= C_INFIX_OP
    else                                            # block operator
        f.arg = _wr_arg(f, 1)

        return sub_term(f, WF_INFIX_BLOCK, sub, f.arg, 1200, W_BLOCK_OP)
    end

    return writeInfixArg2(options, f, sub)
end

# ── canonical (pl-write.c) ──────────────────────────────────────────────────────────────────────

# PORT: pl-write.c writeCanonArg
"The next argument of `f(...)`, after a comma, or the closing `)` (pl-write.c)."
function writeCanonArg(options::write_options{T}, f::wframe{T}, sub::wsub{T})::Int where {T}
    f.n >= f.arity && return Putc(Int(')'), options.out) ? 1 : 0

    f.n > 0 && !PutComma(options) && return 0
    f.arg = _wr_arg(f, f.n + 1)
    f.n += 1

    return sub_term(f, WF_CANON_ARG, sub, f.arg, 999, W_COMPOUND_ARG)
end

# ── write a term (pl-write.c) ───────────────────────────────────────────────────────────────────

# PORT: pl-write.c writeTerm2
# DIVERGES: the term itself, dereferenced (see `wframe`). An atom that is an operator, written
# between parentheses as an operator's argument, returns false if a write fails, where upstream
# goes on to write it as a compound of no arguments into the failed stream (false all the same).
# A compound with no symbol head (`$expr/n`) is written `'$expr'(Child, …)`. NOT PORTED: dicts
# (the kernel has none).
"""
Write `t` at priority `prec` completely (1; 0 on error), or up to its first subterm, filling `f`
and `sub` (`WF_SUB`) (pl-write.c).
"""
function writeTerm2(
    t::T, prec::Int, options::write_options{T}, flags::Int, f::wframe{T}, sub::wsub{T}
)::Int where {T}
    out = options.out
    t = deRef(options.ld, t)

    if kind(t) !== VAR && _ison(options, PL_WRT_PORTRAY)
        rc = callPortray(t, prec, options)
        rc == 1 && return 1
        rc == 0 || return 0                         # error
    end

    if kind(t) === SYM                              # PL_get_atom(t, &a)
        if (flags & W_OP_ARG) != 0 && priorityOperator(options.gd, options.m, t) > 0
            return if (
                PutOpenBrace(options) != 0 && writeAtom(t, options) != 0 &&
                PutCloseBrace(out)
            )
                1
            else
                0
            end
        else
            return writeAtom(t, options) != 0 ? 1 : 0
        end
    end

    kind(t) === EXPR || return writePrimitive(t, options) ? 1 : 0   # !PL_get_name_arity

    h = child(t, 1)
    if kind(h) === SYM
        functor, arity, off = h, nchildren(t) - 1, 1
    else
        functor, arity, off = mk_sym(T, Symbol("\$expr")), nchildren(t), 0
    end

    if _ison(options, PL_WRT_NUMBERVARS | PL_WRT_VARNAMES)
        rc = writeNumberVar(t, options)
        rc == -1 && return 0
        rc == 1 && return 1
    end

    f.t = t
    f.functor = functor
    f.arity = arity
    f.off = off
    f.n = 0
    f.embrace = false

    # handle {a,b,c}
    if !_ison(options, PL_WRT_BRACETERMS) && _is_text_atom_key(functor, options.k_curl) &&
        arity == 1
        arg = _wr_arg(f, 1)
        PutToken("{", out, options.flags) != 0 || return 0

        return sub_term(f, WF_BRACE, sub, arg, 1200, W_TOP)
    end

    # handle Unicode <open>X<close>
    if !_ison(options, PL_WRT_BRACETERMS) && arity == 1
        found, bopen, bclose = bracketPairAtom(functor)
        if found
            arg = _wr_arg(f, 1)
            (PutOpenToken(bopen, out, options.flags) != 0 && Putc(bopen, out)) || return 0
            f.bclose = bclose

            return sub_term(f, WF_BRACKET, sub, arg, 1200, W_TOP)
        end
    end

    # handle lists
    _is_text_atom_key(functor, options.k_dot) && arity == 2 &&
        return writeListStart(t, options, f, sub)

    # operators
    if !_ison(options, PL_WRT_IGNOREOPS) ||
        (
        _is_text_atom_key(functor, options.k_comma) && arity == 2 &&
        _ison(options, PL_WRT_INFIX_COMMA)
    )
        if arity == 1 || (arity == 2 && isBlockOp(t, functor, options))
            # op <term>
            found, op_type, op_pri = currentOperator(
                options.gd, options.m, functor, OP_PREFIX
            )
            if found
                f.op_type = op_type
                f.op_pri = Int(op_pri)
                f.embrace = op_pri > prec

                f.embrace && PutOpenBrace(options) == 0 && return 0
                if arity == 1
                    writeAtom(functor, options) != 0 || return 0
                else
                    f.arg = _wr_arg(f, 1)

                    return sub_term(f, WF_PREFIX_BLOCK, sub, f.arg, 1200, W_BLOCK_OP)
                end

                return writePrefixArg(options, f, sub)
            end

            # <term> op
            found, op_type, op_pri = currentOperator(
                options.gd, options.m, functor, OP_POSTFIX
            )
            if found
                f.op_type = op_type
                f.op_pri = Int(op_pri)
                f.embrace = op_pri > prec

                f.embrace && PutOpenBrace(options) == 0 && return 0
                f.arg = _wr_arg(f, arity)

                return sub_term(
                    f, WF_POSTFIX_ARG, sub, f.arg,
                    op_type == OP_XF ? f.op_pri - 1 : f.op_pri,
                    W_POSTFIX_ARG
                )
            end
        elseif arity == 2 || (arity == 3 && isBlockOp(t, functor, options))
            # <term> op <term>
            found, op_type, op_pri = currentOperator(
                options.gd, options.m, functor, OP_INFIX
            )
            if found
                f.op_type = op_type
                f.op_pri = Int(op_pri)
                f.embrace = op_pri > prec

                f.embrace && PutOpenBrace(options) == 0 && return 0
                f.arg = _wr_arg(f, arity - 1)

                return sub_term(
                    f, WF_INFIX_ARG1, sub, f.arg,
                    op_type == OP_XFX || op_type == OP_XFY ? f.op_pri - 1 : f.op_pri,
                    W_INFIX_ARG1
                )
            end
        end
    end

    # functor(<args> ...)
    (writeAtom(functor, options) != 0 && Putc(Int('('), out)) || return 0

    return writeCanonArg(options, f, sub)
end

# PORT: pl-write.c writeTermResume
"Continue the level `f` after its subterm is written; as `writeTerm2` returns (pl-write.c)."
function writeTermResume(
    options::write_options{T}, f::wframe{T}, sub::wsub{T}
)::Int where {T}
    out = options.out
    k = f.kind

    k == WF_BRACE && return Putc(Int('}'), out) ? 1 : 0
    k == WF_BRACKET && return Putc(f.bclose, out) ? 1 : 0
    k == WF_LIST_ELEM && return writeListElemDone(options, f, sub)
    k == WF_LIST_TAIL && return Putc(Int(']'), out) ? 1 : 0
    k == WF_DOT_HEAD && return writeDotHeadDone(options, f, sub)
    k == WF_DOT_TAIL && return writeCloseParens(options, f) ? 1 : 0
    k == WF_PREFIX_BLOCK && return writePrefixArg(options, f, sub)
    k == WF_POSTFIX_ARG && return writePostfixOp(options, f, sub)
    k == WF_INFIX_ARG1 && return writeInfixOp(options, f, sub)
    k == WF_INFIX_BLOCK && return writeInfixArg2(options, f, sub)
    if k == WF_PREFIX_ARG || k == WF_POSTFIX_BLOCK || k == WF_INFIX_ARG2   # the operator is complete
        return f.embrace ? (PutCloseBrace(out) ? 1 : 0) : 1
    end
    k == WF_CANON_ARG && return writeCanonArg(options, f, sub)

    # WF_LEAF, and the dict kinds (no dicts)
    error("writeTermResume: a level of kind $k")    # assert(0)
end

# PORT: pl-write.c writeTerm
# DIVERGES: the stack is the options' frame pool, a level's frame reused once it is popped (upstream
# pushes a copy of a local frame onto a segstack); no foreign frames (see `wframe`), no
# `discard_wframe` (it frees a dict's order: no dicts); no signals (`PL_handle_signals`).
"Write `t` at priority `prec`, depth by depth on an explicit stack — no recursion (pl-write.c)."
function writeTerm(t::T, prec::Int, options::write_options{T}, flags::Int)::Bool where {T}
    frames = options.frames
    sub = options.sub
    sp = 0                                          # the levels pushed: frames[1:sp]

    @label new_level
    if sp + 1 > length(frames)
        push!(frames, wframe{T}(mk_nil(T)))
    end
    frame = frames[sp + 1]
    frame.kind = WF_LEAF
    frame.depth = options.depth

    options.depth += 1
    if options.depth > options.max_depth && options.max_depth != 0
        options.truncated = true
        PutOpenToken(Int('.'), options.out, options.flags)
        rc = PutElipsis(true, options) ? 1 : 0
    else
        rc = writeTerm2(t, prec, options, flags, frame, sub)
    end
    if rc == WF_SUB
        sp += 1                                     # pushSegStack(&stack, frame, wframe)
        t = sub.t
        prec = sub.prec
        flags = sub.flags

        @goto new_level
    end

    options.depth = frame.depth                     # the level is complete
    rc == 0 && @goto unwind

    while true                                      # resume the enclosing levels
        sp == 0 && return true

        fp = frames[sp]
        rc = writeTermResume(options, fp, sub)
        if rc == WF_SUB
            t = sub.t
            prec = sub.prec
            flags = sub.flags

            @goto new_level
        end

        options.depth = fp.depth
        sp -= 1                                     # popSegStack(&stack, &frame, wframe)
        rc == 0 && @goto unwind
    end

    @label unwind
    while sp > 0
        options.depth = frames[sp].depth
        sp -= 1
    end

    return false
end

# ── cycles and the top level (pl-write.c) ───────────────────────────────────────────────────────

# PORT: pl-write.c writeTopTerm
# DIVERGES: a cyclic term — upstream writes `@(Template, Substitutions)` from `PL_factorize_term` —
# is refused (`NotPortedError`; user, 2026-10-07, decision 4a), checked first, so no write walks a
# cycle; `cycles(false)`'s domain error as upstream. No stream lock (`Slock`).
"Write the term `term` references at priority `prec` (pl-write.c)."
function writeTopTerm(term::term_t, prec::Int, options::write_options{T})::Bool where {T}
    ld = options.ld
    t = ld.slots[term + 1]

    if _ison(options, PL_WRT_PARTIAL) && prec != 999 && prec != 1200
        wflags = W_OP_ARG
    else
        wflags = W_TOP
    end

    if ((options.flags & PL_WRT_NO_CYCLES) == 0 && options.max_depth != 0) ||
        is_acyclic(ld, t)
        rc = writeTerm(t, prec, options, wflags)
    else
        if _ison(options, PL_WRT_NO_CYCLES)
            return PL_error(ld, ERR_DOMAIN, mk_sym(T, :cyclic_term), term)
        end

        throw(
            NotPortedError{T}(
                deRef(ld, t),
                "writing a cyclic term (PL_factorize_term: @(Template, Substitutions))",
                "refused (R1e decision 4a)"
            )
        )
    end

    return rc
end

# PORT: pl-write.c PL_write_term
# DIVERGES: the database and local data are arguments; no stream acquire and release (the stream
# table, R2): the stream's error state is the verdict's, as `PL_release_stream` gives it.
"""
Write the term `term` references to `s` at priority `precedence` with the `PL_WRT_*` `flags`
(pl-write.c): `term_to_atom/2` writes with `PL_WRT_QUOTED`.
"""
function PL_write_term(
    gd::PL_global_data{T}, ld::PL_local_data{T}, s::IOSTREAM, term::term_t, precedence::Int,
    flags::Int
)::Bool where {T}
    options = write_options(gd, ld, s)

    options.flags = flags & ~PL_WRT_NEWLINE
    options.m = MODULE_user(gd)

    if (flags & (PL_WRT_CHARESCAPES | PL_WRT_NO_CHARESCAPES)) == 0
        if (options.m.flags & M_CHARESCAPE) != 0
            options.flags |= PL_WRT_CHARESCAPES
        end
    end

    PutOpenToken(EOF, s, options.flags)             # reset this
    rc = writeTopTerm(term, precedence, options)
    if rc && (flags & PL_WRT_NEWLINE) != 0
        rc = Putc(Int('\n'), s)
    end
    rc = Sferror(s) == 0 && rc                      # PL_release_stream(s) && rc

    return rc
end
