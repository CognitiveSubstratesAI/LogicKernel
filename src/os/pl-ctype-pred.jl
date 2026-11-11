# UPSTREAM: swipl-devel src/os/pl-ctype.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2026, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# CHARACTER TYPES AS PREDICATES (pl-ctype.c), CT1b: `char_type/2` and `code_type/2` and the class tests they run.
# The ASCII table, the locale categories and `setlocale/3`'s data are in src/os/pl-ctype.jl and src/pl-sys.jl; this
# file holds the part of pl-ctype.c that needs the FLI, which is loaded after that file. UNTESTED: written without
# a compile (CT1b writer, edit-only).
#
# DIVERGES (one design change, all of it): upstream's class table holds C function pointers (`test`, `reverse`) and
# `generator` lives in `allocForeignState` memory. Here the two functions are small integers (the fields of `CTF`)
# dispatched by `_ct_test`/`_ct_reverse`, and the generator is a record that `PL_retry` carries packed in one integer
# (`_ct_encode`/`_ct_decode`): the character, the class index and the enumeration flags. A cut needs no freeing.

# PORT: pl-ctype.c CTX_CHAR
"The argument of a class is a character (pl-ctype.c)."
const CTX_CHAR = 0
# PORT: pl-ctype.c CTX_CODE
"The argument of a class is an integer (pl-ctype.c)."
const CTX_CODE = 1

# PORT: pl-ctype.c ENUM_NONE
"Enumerate nothing (pl-ctype.c)."
const ENUM_NONE = 0
# PORT: pl-ctype.c ENUM_CHAR
"Enumerate the characters (pl-ctype.c)."
const ENUM_CHAR = 1
# PORT: pl-ctype.c ENUM_CLASS
"Enumerate the classes (pl-ctype.c)."
const ENUM_CLASS = 2
# PORT: pl-ctype.c ENUM_BOTH
"Enumerate both (pl-ctype.c)."
const ENUM_BOTH = 3

# ── the class tests (pl-ctype.c f_is_* and friends) ─────────────────────────────────────────────────

# PORT: pl-ctype.c f_is_alnum
"Is `chr` Unicode alphanumeric (pl-ctype.c `mkctype(alnum, …)`)?"
f_is_alnum(chr::Int)::Bool = (Int(PL_ctype_flags(chr)) & PL_CTYPE_ALNUM) != 0
# PORT: pl-ctype.c f_is_alpha
"Is `chr` Unicode alphabetic (pl-ctype.c)?"
f_is_alpha(chr::Int)::Bool = (Int(PL_ctype_flags(chr)) & PL_CTYPE_ALPHA) != 0
# PORT: pl-ctype.c f_is_blank
"Is `chr` blank: a space within a line (pl-ctype.c)?"
f_is_blank(chr::Int)::Bool = (Int(PL_ctype_flags(chr)) & PL_CTYPE_BLANK) != 0
# PORT: pl-ctype.c f_is_cntrl
"Is `chr` a control or format character (pl-ctype.c)?"
f_is_cntrl(chr::Int)::Bool = (Int(PL_ctype_flags(chr)) & PL_CTYPE_CNTRL) != 0
# PORT: pl-ctype.c f_is_digit
"Is `chr` an ASCII digit (pl-ctype.c)?"
f_is_digit(chr::Int)::Bool = (Int(PL_ctype_flags(chr)) & PL_CTYPE_DIGIT) != 0
# PORT: pl-ctype.c f_is_eol
"Is `chr` a Unicode line terminator (pl-ctype.c)?"
f_is_eol(chr::Int)::Bool = (Int(PL_ctype_flags(chr)) & PL_CTYPE_EOL) != 0
# PORT: pl-ctype.c f_is_graph
"Is `chr` printable and not white space (pl-ctype.c)?"
f_is_graph(chr::Int)::Bool = (Int(PL_ctype_flags(chr)) & PL_CTYPE_GRAPH) != 0
# PORT: pl-ctype.c f_is_lower
"Is `chr` Unicode lowercase (pl-ctype.c)?"
f_is_lower(chr::Int)::Bool = (Int(PL_ctype_flags(chr)) & PL_CTYPE_LOWER) != 0
# PORT: pl-ctype.c f_is_print
"Is `chr` a graph or white space character (pl-ctype.c)?"
f_is_print(chr::Int)::Bool = (Int(PL_ctype_flags(chr)) & PL_CTYPE_PRINT) != 0
# PORT: pl-ctype.c f_is_punct
"Is `chr` printable and neither alphanumeric nor space (pl-ctype.c)?"
f_is_punct(chr::Int)::Bool = (Int(PL_ctype_flags(chr)) & PL_CTYPE_PUNCT) != 0
# PORT: pl-ctype.c f_is_space
"Is `chr` Unicode White_Space (pl-ctype.c)?"
f_is_space(chr::Int)::Bool = (Int(PL_ctype_flags(chr)) & Int(PL_CTYPE_SPACE)) != 0
# PORT: pl-ctype.c f_is_sterm
"Is `chr` a Unicode Sentence_Terminal (pl-ctype.c)?"
f_is_sterm(chr::Int)::Bool = (Int(PL_ctype_flags(chr)) & PL_CTYPE_STERM) != 0
# PORT: pl-ctype.c f_is_upper
"Is `chr` Unicode uppercase (pl-ctype.c)?"
f_is_upper(chr::Int)::Bool = (Int(PL_ctype_flags(chr)) & PL_CTYPE_UPPER) != 0

# PORT: pl-ctype.c f_is_ascii
"Is `chr` an ASCII code (pl-ctype.c)?"
f_is_ascii(chr::Int)::Bool = chr >= 0 && chr < 128

# PORT: pl-ctype.c fiscsym
"Is `chr` a C identifier character: ASCII letter, digit or `_` (pl-ctype.c)?"
fiscsym(chr::Int)::Bool = isAlpha(chr) || chr == Int('_')

# PORT: pl-ctype.c fiscsymf
"Can `chr` start a C identifier: an ASCII letter or `_` (pl-ctype.c)?"
fiscsymf(chr::Int)::Bool = isLetter(chr) || chr == Int('_')

# PORT: pl-ctype.c iseof
"Is `chr` end of file (pl-ctype.c)?"
iseof(chr::Int)::Bool = chr == -1

# PORT: pl-ctype.c isnl
"Is `chr` a newline (pl-ctype.c)?"
isnl(chr::Int)::Bool = chr == Int('\n')

# ── the mappings (pl-ctype.c ftoupper and friends) ──────────────────────────────────────────────────

# PORT: pl-ctype.c ftoupper
"The Unicode simple uppercase of `chr` (pl-ctype.c)."
ftoupper(chr::Int)::Int = pl_toupper(chr)

# PORT: pl-ctype.c ftolower
"The Unicode simple lowercase of `chr` (pl-ctype.c)."
ftolower(chr::Int)::Int = pl_tolower(chr)

# PORT: pl-ctype.c fupper
"The uppercase of the lowercase letter `chr`, else -1 (pl-ctype.c)."
fupper(chr::Int)::Int = f_is_lower(chr) ? ftoupper(chr) : -1

# PORT: pl-ctype.c flower
"The lowercase of the uppercase letter `chr`, else -1 (pl-ctype.c)."
flower(chr::Int)::Int = f_is_upper(chr) ? ftolower(chr) : -1

# PORT: pl-ctype.c fparen
"The bracket that closes `chr`, else -1 (pl-ctype.c)."
fparen(chr::Int)::Int = f_paren_close(chr)

# PORT: pl-ctype.c rparen
"The bracket that `chr` closes, else -1 (pl-ctype.c)."
rparen(chr::Int)::Int = f_paren_open(chr)

# PORT: pl-ctype.c fwidth
"The display width of `chr` (pl-ctype.c)."
fwidth(chr::Int)::Int = PL_wcwidth(chr)

# PORT: pl-ctype.c fdigit
"The weight of the ASCII digit `chr`, else -1 (pl-ctype.c; `chr <= 0xff && isdigit(chr)`)."
fdigit(chr::Int)::Int = (chr >= Int('0') && chr <= Int('9')) ? chr - Int('0') : -1

# PORT: pl-ctype.c rdigit
"The ASCII digit with weight `d`, else -1 (pl-ctype.c)."
rdigit(d::Int)::Int = (d >= 0 && d <= 9) ? d + Int('0') : -1

# PORT: pl-ctype.c ff_decimal
"The weight of the decimal digit `chr`, in any script, else -1 (pl-ctype.c)."
ff_decimal(chr::Int)::Int = f_is_decimal(chr) ? decimal_weight(chr) : -1

# PORT: pl-ctype.c fxdigit
"The weight of the hexadecimal digit `chr`, else -1 (pl-ctype.c)."
function fxdigit(chr::Int)::Int
    chr > 0xff && return -1
    (chr >= Int('0') && chr <= Int('9')) && return chr - Int('0')
    (chr >= Int('a') && chr <= Int('f')) && return chr - Int('a') + 10
    (chr >= Int('A') && chr <= Int('F')) && return chr - Int('A') + 10
    return -1
end

# PORT: pl-ctype.c rxdigit
"The lowercase hexadecimal digit with weight `d`, else -1 (pl-ctype.c)."
function rxdigit(d::Int)::Int
    (d >= 0 && d <= 9) && return d + Int('0')
    (d >= 10 && d <= 15) && return d - 10 + Int('a')
    return -1
end

# ── the class table (pl-ctype.c char_types) ─────────────────────────────────────────────────────────

# ORIGINAL (CT1b): the numbers that stand for upstream's function pointers in `char_types`: the class tests, then the
# reverse mappings (0: none), as `_ct_test` and `_ct_reverse` read them.
const CTF = (
    alnum = 1, alpha = 2, csym = 3, csymf = 4, prolog_var_start = 5, prolog_atom_start = 6,
    prolog_identifier_continue = 7, decimal = 8, ff_decimal = 9, prolog_symbol = 10,
    prolog_solo = 11, pattern_syntax = 12, ascii = 13, white = 14, cntrl = 15, digit = 16,
    print = 17, graph = 18, lower = 19, upper = 20, punct = 21, space = 22, eof = 23, eol = 24,
    prolog_end_of_line = 25, prolog_layout = 26, newline = 27, period = 28, quote = 29,
    fupper = 30, flower = 31, ftoupper = 32, ftolower = 33, fparen = 34, rparen = 35,
    quote_close = 36, quote_open = 37, fdigit = 38, rdigit = 39, fxdigit = 40, rxdigit = 41,
    fwidth = 42
)

# PORT: pl-ctype.c char_type
# DIVERGES: `name` is the class's text where upstream holds its atom; `test` and `reverse` are `CTF` numbers (0: no
# reverse mapping).
"A character class `char_type/2` knows: its name, arity, test, reverse mapping and the type of its argument (pl-ctype.c)."
struct char_type
    name::String
    test::Int
    reverse::Int
    arity::Int
    ctx_type::Int
end

# PORT: pl-ctype.c char_types
# DIVERGES: a tuple (frozen); its end is its last entry, where upstream's is the `NULL_ATOM` entry.
"The classes of `char_type/2` and `code_type/2`, in upstream's order (pl-ctype.c)."
const char_types = (
    char_type("alnum", CTF.alnum, 0, 0, 0),
    char_type("alpha", CTF.alpha, 0, 0, 0),
    char_type("csym", CTF.csym, 0, 0, 0),
    char_type("csymf", CTF.csymf, 0, 0, 0),
    char_type("prolog_var_start", CTF.prolog_var_start, 0, 0, 0),
    char_type("prolog_atom_start", CTF.prolog_atom_start, 0, 0, 0),
    char_type("prolog_identifier_continue", CTF.prolog_identifier_continue, 0, 0, 0),
    char_type("decimal", CTF.decimal, 0, 0, 0),
    char_type("decimal", CTF.ff_decimal, 0, 1, CTX_CODE),
    char_type("prolog_symbol", CTF.prolog_symbol, 0, 0, 0),
    char_type("prolog_solo", CTF.prolog_solo, 0, 0, 0),
    char_type("pattern_syntax", CTF.pattern_syntax, 0, 0, 0),
    char_type("ascii", CTF.ascii, 0, 0, 0),
    char_type("white", CTF.white, 0, 0, 0),
    char_type("cntrl", CTF.cntrl, 0, 0, 0),
    char_type("digit", CTF.digit, 0, 0, 0),
    char_type("print", CTF.print, 0, 0, 0),
    char_type("graph", CTF.graph, 0, 0, 0),
    char_type("lower", CTF.lower, 0, 0, 0),
    char_type("upper", CTF.upper, 0, 0, 0),
    char_type("punct", CTF.punct, 0, 0, 0),
    char_type("space", CTF.space, 0, 0, 0),
    char_type("end_of_file", CTF.eof, 0, 0, 0),
    char_type("end_of_line", CTF.eol, 0, 0, 0),
    char_type("prolog_end_of_line", CTF.prolog_end_of_line, 0, 0, 0),
    char_type("prolog_layout", CTF.prolog_layout, 0, 0, 0),
    char_type("newline", CTF.newline, 0, 0, 0),
    char_type("period", CTF.period, 0, 0, 0),
    char_type("quote", CTF.quote, 0, 0, 0),
    char_type("lower", CTF.fupper, CTF.flower, 1, CTX_CHAR),
    char_type("upper", CTF.flower, CTF.fupper, 1, CTX_CHAR),
    char_type("to_lower", CTF.ftoupper, CTF.ftolower, 1, CTX_CHAR),
    char_type("to_upper", CTF.ftolower, CTF.ftoupper, 1, CTX_CHAR),
    char_type("paren", CTF.fparen, CTF.rparen, 1, CTX_CHAR),
    char_type("quote", CTF.quote_close, CTF.quote_open, 1, CTX_CHAR),
    char_type("digit", CTF.fdigit, CTF.rdigit, 1, CTX_CODE),
    char_type("xdigit", CTF.fxdigit, CTF.rxdigit, 1, CTX_CODE),
    char_type("width", CTF.fwidth, 0, 1, CTX_CODE)
)

# ORIGINAL (CT1b): `(*cc->test)(chr)` — run the class test numbered `id`; a Boolean test answers 1 or 0.
"The answer of the class test numbered `id` (a `CTF` field) for `chr`: a Boolean test gives 1 or 0, a mapping its value or -1."
function _ct_test(id::Int, chr::Int)::Int
    id == CTF.alnum && return Int(f_is_alnum(chr))
    id == CTF.alpha && return Int(f_is_alpha(chr))
    id == CTF.csym && return Int(fiscsym(chr))
    id == CTF.csymf && return Int(fiscsymf(chr))
    id == CTF.prolog_var_start && return Int(f_is_prolog_var_start(chr))
    id == CTF.prolog_atom_start && return Int(f_is_prolog_atom_start(chr))
    id == CTF.prolog_identifier_continue && return Int(f_is_prolog_identifier_continue(chr))
    id == CTF.decimal && return Int(f_is_decimal(chr))
    id == CTF.ff_decimal && return ff_decimal(chr)
    id == CTF.prolog_symbol && return Int(f_is_prolog_symbol(chr))
    id == CTF.prolog_solo && return Int(f_is_prolog_solo(chr))
    id == CTF.pattern_syntax && return Int(f_is_pattern_syntax(chr))
    id == CTF.ascii && return Int(f_is_ascii(chr))
    id == CTF.white && return Int(f_is_blank(chr))
    id == CTF.cntrl && return Int(f_is_cntrl(chr))
    id == CTF.digit && return Int(f_is_digit(chr))
    id == CTF.print && return Int(f_is_print(chr))
    id == CTF.graph && return Int(f_is_graph(chr))
    id == CTF.lower && return Int(f_is_lower(chr))
    id == CTF.upper && return Int(f_is_upper(chr))
    id == CTF.punct && return Int(f_is_punct(chr))
    id == CTF.space && return Int(f_is_space(chr))
    id == CTF.eof && return Int(iseof(chr))
    id == CTF.eol && return Int(f_is_eol(chr))
    id == CTF.prolog_end_of_line && return Int(is_eol_char(chr))
    id == CTF.prolog_layout && return Int(unicode_separator(chr))
    id == CTF.newline && return Int(isnl(chr))
    id == CTF.period && return Int(f_is_sterm(chr))
    id == CTF.quote && return Int(f_is_quote(chr))
    id == CTF.fupper && return fupper(chr)
    id == CTF.flower && return flower(chr)
    id == CTF.ftoupper && return ftoupper(chr)
    id == CTF.ftolower && return ftolower(chr)
    id == CTF.fparen && return fparen(chr)
    id == CTF.quote_close && return f_quote_close(chr)
    id == CTF.fdigit && return fdigit(chr)
    id == CTF.fxdigit && return fxdigit(chr)
    id == CTF.fwidth && return fwidth(chr)
    error("_ct_test: unknown class test $id")
end

# ORIGINAL (CT1b): `(*cc->reverse)(chr)` — run the reverse mapping numbered `id`.
"The answer of the reverse mapping numbered `id` (a `CTF` field) for `chr`, -1 when it has none."
function _ct_reverse(id::Int, chr::Int)::Int
    id == CTF.flower && return flower(chr)
    id == CTF.fupper && return fupper(chr)
    id == CTF.ftolower && return ftolower(chr)
    id == CTF.ftoupper && return ftoupper(chr)
    id == CTF.rparen && return rparen(chr)
    id == CTF.quote_open && return f_quote_open(chr)
    id == CTF.rdigit && return rdigit(chr)
    id == CTF.rxdigit && return rxdigit(chr)
    error("_ct_reverse: unknown reverse mapping $id")
end

# PORT: pl-ctype.c char_type_by_name
# DIVERGES: the class is its 1-based index in `char_types` (0: none); the name is the atom's text, a blob has none.
"The index of the class `name`/`arity` in `char_types`, 0 if there is none (pl-ctype.c)."
function char_type_by_name(name::T, arity::Int)::Int where {T}
    is_blob(name) && return 0
    s = sym_text(name)
    for (i, cc) in enumerate(char_types)
        cc.name == s && cc.arity == arity && return i
    end
    return 0
end

# ── the generator (pl-ctype.c generator, advanceGen, unify_char_type, do_char_type) ─────────────────

# PORT: pl-ctype.c generator
# DIVERGES: `class` is an index in `char_types`; the record is not in foreign-state memory but packed into the
# `PL_retry` context (`_ct_encode`).
"The state of an enumeration of `char_type/2`: the current character, the current class, what to enumerate (pl-ctype.c)."
mutable struct generator
    current::Int
    class::Int
    do_enum::Int
end

# ORIGINAL (CT1b): the generator as the integer `PL_retry` carries: `current + 1` (0 ..= UNICODE_MAX + 1) in the low
# 22 bits, the class index (1 ..= 37) in the next 8, the enumeration flags above.
"The generator `gen` as the context integer of `PL_retry`."
_ct_encode(gen::generator)::Int = (gen.current + 1) | (gen.class << 22) | (gen.do_enum << 30)

# ORIGINAL (CT1b): the inverse of `_ct_encode`.
"The generator that the context integer `v` of a `PL_retry` encodes."
_ct_decode(v::Int)::generator =
    generator((v & 0x3fffff) - 1, (v >> 22) & 0xff, (v >> 30) & 0x3)

# PORT: pl-ctype.c advanceGen
"Step the generator to its next character, or class; false at the end (pl-ctype.c)."
function advanceGen(gen::generator)::Bool
    if (gen.do_enum & ENUM_CHAR) != 0
        gen.current += 1
        gen.current > UNICODE_MAX && return false
    else
        gen.class += 1
        gen.class > length(char_types) && return false
    end
    return true
end

# PORT: pl-ctype.c unify_char_type
"Unify `type` with the class `ct` — an atom, or a term with the argument `context` as a character or an integer (pl-ctype.c)."
function unify_char_type(
    ld::PL_local_data{T}, type::term_t, ct::char_type, context::Int, how::Symbol
)::Bool where {T}
    name = mk_sym(T, Symbol(ct.name))
    if ct.arity == 0
        return PL_unify_atom(ld, type, name)
    elseif PL_unify_functor(ld, type, name, 1)
        a = PL_new_term_ref(ld)
        _PL_get_arg(ld, 1, type, a)
        ct.ctx_type == CTX_CHAR && return PL_unify_char(ld, a, context, how)
        return PL_unify_integer(ld, a, context)
    end
    return false
end

# ORIGINAL (CT1b): `PL_get_char_ex(chr, &c, true)` (pl-privitf.c, pl-error.c): the character `t` holds, `-1` for the
# integer -1 and the atom `end_of_file`; `nothing` after raising the type error. The kernel's `PL_get_char` takes
# no `eof` (see `PL_unify_char`, src/os/pl-file.jl, which spells out the same two cases).
"The character code of term reference `t` as `PL_get_char_ex(t, &c, true)` reads it, or `nothing` after the error."
function _ct_get_char_ex(ld::PL_local_data{T}, t::term_t)::Union{Nothing, Int} where {T}
    i = PL_get_integer(ld, t)
    i == -1 && return -1
    a = PL_get_atom(ld, t)
    if a !== nothing && sym_key(a) == sym_key(mk_sym(T, :end_of_file))
        return -1
    end
    return PL_get_char(ld, t)
end

# PORT: pl-ctype.c do_char_type
# DIVERGES: see the head of this file for the generator; `how` is `:char` or `:code` (upstream: `PL_CHAR`,
# `PL_CODE`). The foreign frame is opened as upstream does and left to the caller.
"The body of `char_type/2` and `code_type/2`: test, map or enumerate the characters and classes (pl-ctype.c)."
function do_char_type(
    ld::PL_local_data{T}, chr::term_t, class::term_t, h::control_t{T}, how::Symbol
)::foreign_t where {T}
    ctl = PL_foreign_control(h)
    local gen::generator
    if ctl == FRG_FIRST_CALL
        cc = 0                                              # const char_type *cc = NULL
        c = 0
        do_enum = ENUM_NONE
        arity = 0

        PL_is_variable(ld, chr) && (do_enum |= ENUM_CHAR)
        PL_is_variable(ld, class) && (do_enum |= ENUM_CLASS)

        if do_enum == ENUM_BOTH
            PL_error(ld, ERR_INSTANTIATION)
            return FFALSE
        end

        if (do_enum & ENUM_CHAR) == 0
            ch = _ct_get_char_ex(ld, chr)
            ch === nothing && return FFALSE
            c = ch
            c == -1 && return PL_unify_atom(ld, class, mk_sym(T, :end_of_file)) ? FTRUE : FFALSE
        end

        if (do_enum & ENUM_CLASS) == 0
            na = PL_get_name_arity(ld, class)
            cc = na === nothing ? 0 : char_type_by_name(na[1], na[2])
            if cc == 0
                PL_error(ld, ERR_TYPE, mk_sym(T, :char_type), class)
                return FFALSE
            end
            arity = char_types[cc].arity
        end

        if do_enum == ENUM_NONE
            if arity == 0
                return _ct_test(char_types[cc].test, c) != 0 ? FTRUE : FFALSE
            else
                rval = _ct_test(char_types[cc].test, c)

                if rval >= 0
                    a = PL_new_term_ref(ld)
                    _PL_get_arg(ld, 1, class, a)

                    ok = if char_types[cc].ctx_type == CTX_CHAR
                        PL_unify_char(ld, a, rval, how)
                    else
                        PL_unify_integer(ld, a, rval)
                    end

                    ok && return FTRUE
                    do_enum = ENUM_CHAR                     # try the other way around
                else
                    return FFALSE
                end
            end
        end

        if do_enum == ENUM_CHAR && arity == 1 && char_types[cc].reverse != 0
            a = PL_new_term_ref(ld)                         # char_type(X, lower('A'))
            _PL_get_arg(ld, 1, class, a)
            if !PL_is_variable(ld, a)
                ca = PL_get_char(ld, a)
                if ca !== nothing
                    cr = _ct_reverse(char_types[cc].reverse, ca)
                    cr < 0 && return FFALSE
                    return PL_unify_char(ld, chr, cr, how) ? FTRUE : FFALSE
                end
                return FFALSE                               # error
            end
        end

        gen = generator(0, 0, do_enum)
        if (do_enum & ENUM_CHAR) != 0
            gen.class = cc
            gen.current = -1
        elseif (do_enum & ENUM_CLASS) != 0
            gen.class = 1                                   # gen->class = char_types
            gen.current = c
        end
    elseif ctl == FRG_REDO
        gen = _ct_decode(PL_foreign_context(h))
    else                                                    # FRG_CUTTED
        return FTRUE
    end

    fid = PL_open_foreign_frame(ld)
    fid == 0 && return FFALSE                               # goto error

    while true
        cls = char_types[gen.class]
        rval = _ct_test(cls.test, gen.current)

        if (cls.arity == 0 && rval != 0) || (cls.arity > 0 && rval >= 0)
            found = true
            if (gen.do_enum & ENUM_CHAR) != 0
                if !PL_unify_char(ld, chr, gen.current, how)
                    ld.exception_term != 0 && return FFALSE     # goto error
                    found = false                               # goto next
                end
            end
            if found && ((gen.do_enum & ENUM_CLASS) != 0 || cls.arity > 0)
                if !unify_char_type(ld, class, cls, rval, how)
                    ld.exception_term != 0 && return FFALSE
                    found = false
                end
            end

            if found
                advanceGen(gen) && return PL_retry(_ct_encode(gen))    # ok, found one: ForeignRedoPtr(gen)
                return FTRUE                                    # the only one
            end
        end
        PL_rewind_foreign_frame(ld, fid)                        # next:

        advanceGen(gen) || break
    end
    return FFALSE                                               # error:
end

# PORT: pl-ctype.c char_type as pl_char_type2_va
# (PRED_IMPL("char_type", 2, char_type, PL_FA_NONDETERMINISTIC))
"`char_type(?Char, ?Type)`: a character and the classes it belongs to (pl-ctype.c)."
function pl_char_type2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return do_char_type(ld, PL__t0, PL__t0 + 1, PL__ctx, :char)
end

# PORT: pl-ctype.c code_type as pl_code_type2_va
# (PRED_IMPL("code_type", 2, code_type, PL_FA_NONDETERMINISTIC))
"`code_type(?Code, ?Type)`: as `char_type/2`, the character as a code (pl-ctype.c)."
function pl_code_type2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return do_char_type(ld, PL__t0, PL__t0 + 1, PL__ctx, :code)
end

# PORT: pl-ctype.c BeginPredDefs as PL_predicates_from_ctype_pred
# DIVERGES: upstream's one `ctype` table (`PL_predicates_from_ctype`, src/pl-sys.jl holds `setlocale/3`'s entry) is
# split in two, as this file loads after src/pl-sys.jl; this table is appended last in `_PRED_TABLES`
# (src/pl-ext.jl), so the dispatch indices of the earlier tables stay as they were.
"pl-ctype.c's registration table (`BeginPredDefs(ctype)`), the part this file ports."
const PL_predicates_from_ctype_pred = (
    PL_extension("char_type", 2, pl_char_type2_va, PL_FA_NONDETERMINISTIC | PL_FA_VARARGS),
    PL_extension("code_type", 2, pl_code_type2_va, PL_FA_NONDETERMINISTIC | PL_FA_VARARGS),
)
