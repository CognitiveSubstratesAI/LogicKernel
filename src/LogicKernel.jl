# ORIGINAL: the module entry file — includes and exports only; no upstream counterpart.
"""
    LogicKernel

A standalone logic-programming kernel: terms, unification, a clause database, argument
indexing, term tries, SLG tabling and a clause VM — with NO MeTTa semantics. Answers come back
in order with duplicates kept; deduplication and tabling modes are caller options.

The source layout mirrors swipl-devel (see `docs/architecture.md`). Implemented so far: `terms` — the term interface, the default term type
[`Term`](@ref), and SWI-Prolog's standard order of terms ([`compareStandard`](@ref)); `index` —
SWI-Prolog's just-in-time clause indexing (src/pl-index.jl), over the clause lists of
src/pl-incl.jl and src/pl-proc.jl. The index is internal until the clause database gives it a
public API.
"""
module LogicKernel

# ── includes, in dependency order ───────────────────────────────────────────────────────────────
# The layout MIRRORS swipl-devel (user, 2026-10-02): a port of swipl-devel `src/pl-x.c` is
# `src/pl-x.jl`, a port of `boot/x.pl` is `boot/x.jl`; code with no SWI counterpart is in `src/` with
# an `# ORIGINAL:` header. Subsystems are a grouping in docs/architecture.md, not directories.
# tools/port_check.jl enforces all of it.
include("term_interface.jl")   # ORIGINAL — the term interface (settled 2026-10-02)
include("pl-prims.jl")         # swipl-devel src/pl-prims.c — the standard order of terms
include("default_term.jl")     # ORIGINAL — Term{G}, the reference implementation
include("pl-hash.jl")          # swipl-devel src/pl-hash.c — MurmurHash2
include("pl-incl.jl")          # swipl-devel src/pl-incl.h — clause, clause list, index structs
include("pl-vmi.jl")           # swipl-devel src/pl-vmi.c — the VM instructions heads compile to
include("pl-comp.jl")          # swipl-devel src/pl-comp.c — compiling clause heads; reading code
include("pl-index.jl")         # swipl-devel src/pl-index.c — just-in-time clause indexing
include("pl-proc.jl")          # swipl-devel src/pl-proc.c — predicates, adding clauses

# ── exports ─────────────────────────────────────────────────────────────────────────────────────
# the term interface (src/term_interface.jl)
export Kind, VAR, SYM, GND, EXPR
export kind,
    nchildren, child, sym_key, sym_hash, var_key, gnd_key, gnd_equal, atomic_compare
export mk_var, mk_expr, is_ground, is_ground_walk
# the standard order of terms — SWI-Prolog's name (src/pl-prims.jl)
export compareStandard
# the default term type (src/default_term.jl)
export Term, DefaultTerm, sym_term, gnd_term, gnd_value_key, sym_name, gnd_value

end # module LogicKernel
