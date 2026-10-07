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
