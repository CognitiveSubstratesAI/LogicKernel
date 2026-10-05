# UPSTREAM: swipl-devel src/SWI-Prolog.h @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  2008-2026, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# What the kernel takes from SWI-Prolog's public C interface header (SWI-Prolog.h): the flags a
# query is opened with and the codes `PL_next_solution` returns (decision 1). Not ported: the flags
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
