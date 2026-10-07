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
# name (`unquoted_atom`: may it be written without quotes? then it is no operator), with no write
# options (`atomType` and `unquoted_text` as upstream calls them from `unquoted_atom`). NOT PORTED:
# everything else, R1e — `writeTerm2`, operators and spacing, `format_float`, `write/1`,
# `writeq/1`, `print/1`, `write_canonical/1`, `write_term/2,3`, `nl/0,1`.

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
"`atomType`: an unquoted identifier (pl-write.c)."
const AT_LOWER = 0
# PORT: pl-write.c AT_QUOTE
"`atomType`: must be quoted (pl-write.c)."
const AT_QUOTE = 1
# PORT: pl-write.c AT_FULLSTOP
"`atomType`: the atom `.` (pl-write.c)."
const AT_FULLSTOP = 2
# PORT: pl-write.c AT_SYMBOL
"`atomType`: symbol characters (pl-write.c)."
const AT_SYMBOL = 3
# PORT: pl-write.c AT_SOLO
"`atomType`: a solo character (pl-write.c)."
const AT_SOLO = 4
# PORT: pl-write.c AT_SPECIAL
"`atomType`: `[]` or `{}` (pl-write.c)."
const AT_SPECIAL = 5

# PORT: pl-write.c wr_is_symbol
# DIVERGES: no write options (`PL_WRT_BACKQUOTE_IS_SYMBOL`), R1e.
"Is `c` a symbol character for the writer (pl-write.c)?"
wr_is_symbol(c::Int)::Bool = f_is_prolog_symbol(c)

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

# PORT: pl-write.c atomType
# DIVERGES: the atom's text (`sym_text`) with no write options: `options` NULL as `unquoted_atom`
# passes it — so no stream, no flags, the `user` module, whose `var_prefix` is off; `dot_in_atom`
# off (SWI-7's default).
"How the single-byte atom with text `name` must be written (pl-write.c `AT_*`)."
function atomType(name::String)::Int
    cs = collect(name)
    n = length(cs)
    n == 0 && return AT_QUOTE
    c0 = Int(cs[1])
    if f_is_prolog_atom_start(c0)
        k = 2
        while k <= n && f_is_prolog_identifier_continue(Int(cs[k])) &&
              !code_requires_quoted(Int(cs[k]), nothing, 0)
            k += 1
        end
        return k > n ? AT_LOWER : AT_QUOTE
    end
    if wr_is_symbol(c0)
        n == 1 && cs[1] == '.' && return AT_FULLSTOP
        n >= 2 && cs[1] == '/' && cs[2] == '*' && return AT_QUOTE
        k = 1
        while k <= n && wr_is_symbol(Int(cs[k])) &&
              !code_requires_quoted(Int(cs[k]), nothing, 0)
            k += 1
        end
        k <= n && return AT_QUOTE
        return AT_SYMBOL
    end
    if n == 1 && cs[1] != '%'                       # % should be quoted!
        wr_is_solo(c0, 0) && return AT_SOLO
    end
    # a == ATOM_nil || a == ATOM_curl: ATOM_nil is SWI-7's `[]`, a reserved symbol, never the
    # text atom `'[]'` (written quoted: probed), so only `{}` is AT_SPECIAL by its text
    name == "{}" && return AT_SPECIAL
    return AT_QUOTE
end

# PORT: pl-write.c unquoted_text
# DIVERGES: the text is a String, its characters taken in turn (`text_next_char`); `dot_in_atom`
# off (SWI-7's default).
"May the text be written to `fd` with `flags` as an atom without quotes (pl-write.c)?"
function unquoted_text(text::String, fd::Union{Nothing, IOSTREAM}, flags::Int)::Bool
    cs = collect(text)
    isempty(cs) && return false
    c = Int(cs[1])
    if length(cs) == 1                              # single character atom
        wr_is_solo(c, flags) && return true
    elseif c >= 0x80                                # '<open><close>' prints like {}
        length(cs) == 2 && f_paren_close(c) == Int(cs[2]) && return true
    end
    if !f_is_prolog_atom_start(c)                   # Sequence of symbol chars
        for ch in cs
            (f_is_prolog_symbol(Int(ch)) && !code_requires_quoted(Int(ch), fd, flags)) ||
                return false
        end
        return true
    end
    code_requires_quoted(c, fd, flags) && return false
    for k in 2:length(cs)                           # 1st char is ID_START
        ch = Int(cs[k])
        (f_is_prolog_identifier_continue(ch) && !code_requires_quoted(ch, fd, flags)) ||
            return false
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
    any(ch -> Int(ch) > 0xff, name) && return unquoted_atomW(name, nothing, 0)
    return atomType(name) != AT_QUOTE
end
