# UPSTREAM: swipl-devel src/pl-modul.c @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-incl.h @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# What the kernel takes from SWI-Prolog's modules (pl-modul.c): so far, what a call of an undefined
# predicate reads — the module's `unknown` flag (V5b). The module records themselves are
# src/pl-incl.jl's `module_t`, `user` and `system`; `user` reaches `system` (super modules,
# `autoImport`) from V5c on, as decided since Q-A.

# PORT: pl-incl.h UNKNOWN_FAIL
"The `unknown` flag's `fail`: an undefined predicate fails silently (pl-incl.h)."
const UNKNOWN_FAIL = 0x00001000
# PORT: pl-incl.h UNKNOWN_WARNING
"The `unknown` flag's `warning`: print a warning, then fail (pl-incl.h)."
const UNKNOWN_WARNING = 0x00002000
# PORT: pl-incl.h UNKNOWN_ERROR
"The `unknown` flag's `error`, the default: raise `existence_error(procedure, PI)` (pl-incl.h)."
const UNKNOWN_ERROR = 0x00004000

# PORT: pl-modul.c getUnknownModule
# DIVERGES: a module has no flags here (`module_t` is its name and its procedures), so nothing can
# set `unknown` and `inheritUnknown` finds none: the default, `UNKNOWN_ERROR`, as upstream returns
# when no module in the chain sets the flag. `S_UNDEF`'s warning and fail branches are therefore not
# reachable, and not ported (src/pl-wam.jl).
"The `unknown` flag in force for module `m` (pl-modul.c): `UNKNOWN_ERROR`, the default."
getUnknownModule(m::module_t{T}) where {T} = UNKNOWN_ERROR
