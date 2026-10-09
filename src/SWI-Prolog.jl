# UPSTREAM: swipl-devel src/SWI-Prolog.h @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  2008-2026, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# What the kernel takes from SWI-Prolog's public C interface header (SWI-Prolog.h): the flags a
# query is opened with and the codes `PL_next_solution` returns (decision 1); since V5a2 the types
# and the registration record of the foreign interface (decision 5). Not ported: the flags
# of the parts decision 1 leaves out — `PL_Q_ALLOW_YIELD`, `PL_Q_EXCEPT_HALT`,
# `PL_Q_TRACE_WITH_YIELD`, `PL_Q_EXCEPT_THREAD_EXIT` — and the yield codes `PL_S_YIELD_DEBUG`,
# `PL_S_YIELD`.

# PORT: SWI-Prolog.h PL_Q_DEBUG
"Query flag: `true`, for backward compatibility; opened as `PL_Q_NORMAL` (SWI-Prolog.h)."
const PL_Q_DEBUG = UInt32(0x0001)
# PORT: SWI-Prolog.h PL_Q_NORMAL
"Query flag: debug and print exceptions, return a bool (SWI-Prolog.h)."
const PL_Q_NORMAL = UInt32(0x0002)
# PORT: SWI-Prolog.h PL_Q_NODEBUG
"Query flag: run in nodebug mode (SWI-Prolog.h)."
const PL_Q_NODEBUG = UInt32(0x0004)
# PORT: SWI-Prolog.h PL_Q_CATCH_EXCEPTION
"Query flag: the caller handles an exception (SWI-Prolog.h)."
const PL_Q_CATCH_EXCEPTION = UInt32(0x0008)
# PORT: SWI-Prolog.h PL_Q_PASS_EXCEPTION
"Query flag: pass an exception to the parent environment (SWI-Prolog.h)."
const PL_Q_PASS_EXCEPTION = UInt32(0x0010)
# PORT: SWI-Prolog.h PL_Q_EXT_STATUS
"Query flag: return the extended status, `PL_S_*` (SWI-Prolog.h)."
const PL_Q_EXT_STATUS = UInt32(0x0040)
# PORT: SWI-Prolog.h PL_Q_DETERMINISTIC
"Query flag, the engine's own: the call was deterministic (SWI-Prolog.h)."
const PL_Q_DETERMINISTIC = UInt32(0x1000)

# PORT: SWI-Prolog.h PL_S_NOT_INNER
"`PL_next_solution`, cut or close of a query that is not the innermost (SWI-Prolog.h)."
const PL_S_NOT_INNER = -2
# PORT: SWI-Prolog.h PL_S_EXCEPTION
"The query raised an exception (SWI-Prolog.h)."
const PL_S_EXCEPTION = -1
# PORT: SWI-Prolog.h PL_S_FALSE
"The query failed (SWI-Prolog.h)."
const PL_S_FALSE = 0
# PORT: SWI-Prolog.h PL_S_TRUE
"The query succeeded, leaving a choice point (SWI-Prolog.h)."
const PL_S_TRUE = 1
# PORT: SWI-Prolog.h PL_S_LAST
"The query succeeded without a choice point (SWI-Prolog.h)."
const PL_S_LAST = 2

# ── the foreign interface (decision 5; V5a2) ─────────────────────────────────────────────────────
# PORT: SWI-Prolog.h term_t
"A term reference (SWI-Prolog.h `term_t`): a position on the local stack (src/pl-incl.jl)."
const term_t = Int
# PORT: SWI-Prolog.h PL_fid_t as fid_t
"A foreign frame handle (SWI-Prolog.h `PL_fid_t`, `fid_t`): the frame's position."
const fid_t = Int
# PORT: SWI-Prolog.h foreign_t
"What a foreign predicate returns (SWI-Prolog.h `foreign_t`, a `uintptr_t`)."
const foreign_t = UInt
# PORT: SWI-Prolog.h TRUE as FTRUE
# DIVERGES: named `FTRUE`/`FFALSE` — `true` and `false` are Julia's `Bool`s; upstream's are the
# `int` values 1 and 0, which a foreign predicate returns.
"A foreign predicate succeeded: `foreign_t` 1 (SWI-Prolog.h `TRUE`)."
const FTRUE = foreign_t(1)
# PORT: SWI-Prolog.h FALSE as FFALSE
"A foreign predicate failed (or raised, when an exception is pending): `foreign_t` 0 (SWI-Prolog.h `FALSE`)."
const FFALSE = foreign_t(0)

# PORT: SWI-Prolog.h PL_FA_NOTRACE
"Registration flag: the foreign predicate cannot be traced (SWI-Prolog.h)."
const PL_FA_NOTRACE = 0x01
# PORT: SWI-Prolog.h PL_FA_TRANSPARENT
"Registration flag: module transparent, deprecated (SWI-Prolog.h)."
const PL_FA_TRANSPARENT = 0x02
# PORT: SWI-Prolog.h PL_ATOM
"Text type: an atom (SWI-Prolog.h)."
const PL_ATOM = 2
# PORT: SWI-Prolog.h PL_STRING
"Text type: a string (SWI-Prolog.h)."
const PL_STRING = 6
# PORT: SWI-Prolog.h CVT_ATOM
"Text conversion: an atom (SWI-Prolog.h)."
const CVT_ATOM = 0x00000001
# PORT: SWI-Prolog.h CVT_STRING
"Text conversion: a string (SWI-Prolog.h)."
const CVT_STRING = 0x00000002
# PORT: SWI-Prolog.h CVT_LIST
"Text conversion: a code or character list (SWI-Prolog.h)."
const CVT_LIST = 0x00000004
# PORT: SWI-Prolog.h CVT_INTEGER
"Text conversion: an integer (SWI-Prolog.h)."
const CVT_INTEGER = 0x00000008
# PORT: SWI-Prolog.h CVT_RATIONAL
"Text conversion: a rational number (SWI-Prolog.h)."
const CVT_RATIONAL = 0x00000010
# PORT: SWI-Prolog.h CVT_FLOAT
"Text conversion: a float (SWI-Prolog.h)."
const CVT_FLOAT = 0x00000020
# PORT: SWI-Prolog.h CVT_VARIABLE
"Text conversion: a variable's name (SWI-Prolog.h)."
const CVT_VARIABLE = 0x00000040
# PORT: SWI-Prolog.h CVT_NUMBER
"Text conversion: a number (SWI-Prolog.h)."
const CVT_NUMBER = CVT_RATIONAL | CVT_FLOAT
# PORT: SWI-Prolog.h CVT_ATOMIC
"Text conversion: an atomic term (SWI-Prolog.h)."
const CVT_ATOMIC = CVT_NUMBER | CVT_ATOM | CVT_STRING
# PORT: SWI-Prolog.h CVT_WRITE
"Text conversion: any term, as `write/1` writes it (SWI-Prolog.h)."
const CVT_WRITE = 0x00000080
# PORT: SWI-Prolog.h CVT_WRITE_CANONICAL
"Text conversion: any term, as `write_canonical/1` writes it (SWI-Prolog.h)."
const CVT_WRITE_CANONICAL = 0x00000100
# PORT: SWI-Prolog.h CVT_WRITEQ
"Text conversion: any term, as `writeq/1` writes it (SWI-Prolog.h)."
const CVT_WRITEQ = 0x00000200
# PORT: SWI-Prolog.h CVT_ALL
"Text conversion: an atomic term or a list (SWI-Prolog.h)."
const CVT_ALL = CVT_ATOMIC | CVT_LIST
# PORT: SWI-Prolog.h CVT_XINTEGER
"Text conversion: an integer, in hexadecimal (SWI-Prolog.h)."
const CVT_XINTEGER = 0x00000400 | CVT_INTEGER
# PORT: SWI-Prolog.h CVT_EXCEPTION
"Text conversion: raise an error where the conversion fails (SWI-Prolog.h)."
const CVT_EXCEPTION = 0x00001000
# PORT: SWI-Prolog.h CVT_VARNOFAIL
"Text conversion: report an unbound argument instead of failing (SWI-Prolog.h)."
const CVT_VARNOFAIL = 0x00002000
# PORT: SWI-Prolog.h PL_WRT_QUOTED
"Write flag: quote atoms and strings (SWI-Prolog.h)."
const PL_WRT_QUOTED = Int(0x01)
# PORT: SWI-Prolog.h PL_WRT_IGNOREOPS
"Write flag: ignore list/operators (SWI-Prolog.h)."
const PL_WRT_IGNOREOPS = Int(0x02)
# PORT: SWI-Prolog.h PL_WRT_NUMBERVARS
"Write flag: print \$VAR(N) as a variable (SWI-Prolog.h)."
const PL_WRT_NUMBERVARS = Int(0x04)
# PORT: SWI-Prolog.h PL_WRT_PORTRAY
"Write flag: call portray (SWI-Prolog.h)."
const PL_WRT_PORTRAY = Int(0x08)
# PORT: SWI-Prolog.h PL_WRT_CHARESCAPES
"Write flag: Output ISO escape sequences (SWI-Prolog.h)."
const PL_WRT_CHARESCAPES = Int(0x10)
# PORT: SWI-Prolog.h PL_WRT_BACKQUOTED_STRING
"Write flag: Write strings as `...` (SWI-Prolog.h)."
const PL_WRT_BACKQUOTED_STRING = Int(0x20)
# PORT: SWI-Prolog.h PL_WRT_ATTVAR_IGNORE
"Write flag: Default: just write the var (SWI-Prolog.h)."
const PL_WRT_ATTVAR_IGNORE = Int(0x040)
# PORT: SWI-Prolog.h PL_WRT_ATTVAR_DOTS
"Write flag: Write as Var{...} (SWI-Prolog.h)."
const PL_WRT_ATTVAR_DOTS = Int(0x080)
# PORT: SWI-Prolog.h PL_WRT_ATTVAR_WRITE
"Write flag: Write as Var{Attributes} (SWI-Prolog.h)."
const PL_WRT_ATTVAR_WRITE = Int(0x100)
# PORT: SWI-Prolog.h PL_WRT_ATTVAR_PORTRAY
"Write flag: Use Module:portray_attrs/2 (SWI-Prolog.h)."
const PL_WRT_ATTVAR_PORTRAY = Int(0x200)
# PORT: SWI-Prolog.h PL_WRT_BLOB_PORTRAY
"Write flag: Use portray for non-text blobs (SWI-Prolog.h)."
const PL_WRT_BLOB_PORTRAY = Int(0x400)
# PORT: SWI-Prolog.h PL_WRT_NO_CYCLES
"Write flag: Never emit @(Template,Subst) (SWI-Prolog.h)."
const PL_WRT_NO_CYCLES = Int(0x800)
# PORT: SWI-Prolog.h PL_WRT_NEWLINE
"Write flag: Add a newline (SWI-Prolog.h)."
const PL_WRT_NEWLINE = Int(0x2000)
# PORT: SWI-Prolog.h PL_WRT_VARNAMES
"Write flag: Internal: variable_names(List) (SWI-Prolog.h)."
const PL_WRT_VARNAMES = Int(0x4000)
# PORT: SWI-Prolog.h PL_WRT_BACKQUOTE_IS_SYMBOL
"Write flag: ` is a symbol char (SWI-Prolog.h)."
const PL_WRT_BACKQUOTE_IS_SYMBOL = Int(0x8000)
# PORT: SWI-Prolog.h PL_WRT_DOTLISTS
"Write flag: Write lists as .(A,B) (SWI-Prolog.h)."
const PL_WRT_DOTLISTS = Int(0x10000)
# PORT: SWI-Prolog.h PL_WRT_BRACETERMS
"Write flag: Write {A} as {}(A) (SWI-Prolog.h)."
const PL_WRT_BRACETERMS = Int(0x20000)
# PORT: SWI-Prolog.h PL_WRT_NODICT
"Write flag: Do not write dicts pretty (SWI-Prolog.h)."
const PL_WRT_NODICT = Int(0x40000)
# PORT: SWI-Prolog.h PL_WRT_NODOTINATOM
"Write flag: never write a.b unquoted (SWI-Prolog.h)."
const PL_WRT_NODOTINATOM = Int(0x80000)
# PORT: SWI-Prolog.h PL_WRT_NO_LISTS
"Write flag: Do not write lists as [...] (SWI-Prolog.h)."
const PL_WRT_NO_LISTS = Int(0x100000)
# PORT: SWI-Prolog.h PL_WRT_RAT_NATURAL
"Write flag: Write rationals as 1/3 (SWI-Prolog.h)."
const PL_WRT_RAT_NATURAL = Int(0x200000)
# PORT: SWI-Prolog.h PL_WRT_CHARESCAPES_UNICODE
"Write flag: Use \\uXXXX escapes (SWI-Prolog.h)."
const PL_WRT_CHARESCAPES_UNICODE = Int(0x400000)
# PORT: SWI-Prolog.h PL_WRT_QUOTE_NON_ASCII
"Write flag: quote atoms containing non-ASCII (SWI-Prolog.h)."
const PL_WRT_QUOTE_NON_ASCII = Int(0x800000)
# PORT: SWI-Prolog.h PL_WRT_PARTIAL
"Write flag: Partial output (SWI-Prolog.h)."
const PL_WRT_PARTIAL = Int(0x1000000)
# PORT: SWI-Prolog.h PL_WRT_NO_CHARESCAPES
"Write flag: Do not Output ISO escapes (SWI-Prolog.h)."
const PL_WRT_NO_CHARESCAPES = Int(0x2000000)
# PORT: SWI-Prolog.h PL_WRT_INFIX_COMMA
"Write flag: Write (a,b), with PL_WRT_IGNOREOPS (SWI-Prolog.h)."
const PL_WRT_INFIX_COMMA = Int(0x4000000)
# PORT: SWI-Prolog.h PL_WRT_PATTERN_SYNTAX_SOLO
"Write flag: quote single-character solo atoms outside Pattern_Syntax (SWI-Prolog.h)."
const PL_WRT_PATTERN_SYNTAX_SOLO = Int(0x8000000)
# PORT: SWI-Prolog.h PL_WRT_PORTABLE
"Write flags: ignore operators, but write `(a,b)` with the comma (SWI-Prolog.h)."
const PL_WRT_PORTABLE = PL_WRT_IGNOREOPS | PL_WRT_INFIX_COMMA
# PORT: SWI-Prolog.h PL_CTYPE_SPACE
"Character class: Unicode White_Space (SWI-Prolog.h `PL_ctype_flags`)."
const PL_CTYPE_SPACE = 0x0400
# PORT: SWI-Prolog.h PL_FA_NONDETERMINISTIC
"Registration flag: non-deterministic (SWI-Prolog.h)."
const PL_FA_NONDETERMINISTIC = 0x04
# PORT: SWI-Prolog.h PL_FA_VARARGS
"Registration flag: called with `t0, ac, ctx` (SWI-Prolog.h)."
const PL_FA_VARARGS = 0x08
# PORT: SWI-Prolog.h PL_FA_CREF
"Registration flag, internal: has a clause reference (SWI-Prolog.h)."
const PL_FA_CREF = 0x10
# PORT: SWI-Prolog.h PL_FA_ISO
"Registration flag, internal: an ISO core predicate (SWI-Prolog.h)."
const PL_FA_ISO = 0x20
# PORT: SWI-Prolog.h PL_FA_META
"Registration flag: an additional meta-argument spec (SWI-Prolog.h)."
const PL_FA_META = 0x40
# PORT: SWI-Prolog.h PL_FA_SIG_ATOMIC
"Registration flag, internal: do not dispatch signals (SWI-Prolog.h)."
const PL_FA_SIG_ATOMIC = 0x80

# PORT: SWI-Prolog.h PL_extension
# DIVERGES: `function` is a Julia keyword, so the field is `function_`; it holds the Julia function
# itself (a singleton type), where upstream holds a `pl_function_t` pointer — a table of them is a
# TUPLE, concretely typed, so reading an entry dispatches statically (decision 5). `arity` is an
# `Int` and `flags` a `UInt8`, where upstream has `short`s (every `PL_FA_*` flag fits).
"One predicate of a registration table (SWI-Prolog.h `PL_extension`)."
struct PL_extension{F}
    predicate_name::String          # Name of the predicate
    arity::Int                      # Arity of the predicate
    function_::F                    # Implementing functions
    flags::UInt8                    # Or of PL_FA_...
end

# ── option processing (SWI-Prolog.h `_PL_opt_type`, `PL_option_t`), since R1e's write_term ────────

# PORT: SWI-Prolog.h OPT_BOOL
"Option type: a Boolean, `true`/`false` (`on`/`off`, `1`/`0`) (SWI-Prolog.h)."
const OPT_BOOL = 0
# PORT: SWI-Prolog.h OPT_INT
"Option type: a C `int` (SWI-Prolog.h)."
const OPT_INT = 1
# PORT: SWI-Prolog.h OPT_INT64
"Option type: a 64-bit integer (SWI-Prolog.h)."
const OPT_INT64 = 2
# PORT: SWI-Prolog.h OPT_UINT64
"Option type: an unsigned 64-bit integer (SWI-Prolog.h)."
const OPT_UINT64 = 3
# PORT: SWI-Prolog.h OPT_SIZE
"Option type: a `size_t` (SWI-Prolog.h)."
const OPT_SIZE = 4
# PORT: SWI-Prolog.h OPT_DOUBLE
"Option type: a float (SWI-Prolog.h)."
const OPT_DOUBLE = 5
# PORT: SWI-Prolog.h OPT_STRING
"Option type: a text, as UTF-8 (SWI-Prolog.h)."
const OPT_STRING = 6
# PORT: SWI-Prolog.h OPT_ATOM
"Option type: an atom (SWI-Prolog.h)."
const OPT_ATOM = 7
# PORT: SWI-Prolog.h OPT_TERM
"Option type: any term, as a term reference (SWI-Prolog.h)."
const OPT_TERM = 8
# PORT: SWI-Prolog.h OPT_LOCALE
"Option type: a locale (SWI-Prolog.h)."
const OPT_LOCALE = 9
# PORT: SWI-Prolog.h OPT_STDBOOL
"Option type: a C11 `bool` (SWI-Prolog.h)."
const OPT_STDBOOL = 10

# PORT: SWI-Prolog.h OPT_TYPE_MASK
"The type bits of an option's `type` (SWI-Prolog.h)."
const OPT_TYPE_MASK = Int(0xff)
# PORT: SWI-Prolog.h OPT_INF
"Option type bit: `inf` allowed (SWI-Prolog.h)."
const OPT_INF = Int(0x100)

# PORT: SWI-Prolog.h OPT_UNKNOWN_DEFAULT
"Unknown options: as the `unknown_option` flag says (SWI-Prolog.h)."
const OPT_UNKNOWN_DEFAULT = Int(0x0)
# PORT: SWI-Prolog.h OPT_UNKNOWN_ERROR
"Unknown options raise a domain error (SWI-Prolog.h)."
const OPT_UNKNOWN_ERROR = Int(0x1)
# PORT: SWI-Prolog.h OPT_UNKNOWN_IGNORE
"Unknown options are ignored (SWI-Prolog.h)."
const OPT_UNKNOWN_IGNORE = Int(0x2)
# PORT: SWI-Prolog.h OPT_UNKNOWN_WARNING
"Unknown options print a warning (SWI-Prolog.h)."
const OPT_UNKNOWN_WARNING = Int(0x3)
# PORT: SWI-Prolog.h OPT_UNKNOWN_MASK
"The unknown-option bits of `PL_scan_options`' flags (SWI-Prolog.h)."
const OPT_UNKNOWN_MASK = Int(0x3)

# PORT: SWI-Prolog.h PL_option_t
# DIVERGES: the name is the atom's text (a `Symbol`), compared by its key in the term type a scan
# runs on, where upstream holds an `atom_t`; no `string` (the API stub's form, which fills `name`).
"An option's specification: its name and its `OPT_*` type (SWI-Prolog.h `PL_option_t`)."
struct PL_option_t
    name::Symbol                    # Name of the option
    type::Int                       # Type of the option
end
