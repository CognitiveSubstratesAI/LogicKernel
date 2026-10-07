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
include("default_term.jl")     # ORIGINAL — Term{G}, the reference implementation
include("pl-hash.jl")          # swipl-devel src/pl-hash.c — MurmurHash2
include("pl-incl.jl")          # swipl-devel src/pl-incl.h — clause, clause list, index structs
include("SWI-Prolog.jl")       # swipl-devel src/SWI-Prolog.h — query flags and return codes
include("pl-termwalk.jl")      # swipl-devel src/pl-termwalk.c — term agendas (the local data holds two)
include("pl-vmi.jl")           # swipl-devel src/pl-vmi.c — the VM instructions heads compile to (pl-index reads them)
include("pl-index.jl")         # swipl-devel src/pl-index.c — just-in-time clause indexing (LD holds its scratch)
include("pl-funct.jl")         # swipl-devel src/pl-funct.c — the control functors (GD holds them)
include("pl-global.jl")        # swipl-devel src/pl-global.h — the database state (GD, LD)
include("pl-modul.jl")         # swipl-devel src/pl-modul.c — a module's `unknown` flag
include("pl-inline.jl")        # swipl-devel src/pl-inline.h — visibility, generations, keys, bindings
include("pl-prims.jl")         # swipl-devel src/pl-prims.c — the standard order; unification
include("pl-ressymbol.jl")     # swipl-devel src/pl-ressymbol.c — reserved symbols (SWI-7's `[]`)
include("pl-comp.jl")          # swipl-devel src/pl-comp.c — compiling clause heads; clause/2
include("pl-variant.jl")       # swipl-devel src/pl-variant.c — =@=, variant checking
include("pl-termhash.jl")      # swipl-devel src/pl-termhash.c — term_hash, variant_sha1/hash
include("pl-thread.jl")        # swipl-devel src/pl-thread.c — predicate references
include("pl-gc.jl")            # swipl-devel src/pl-gc.c — generations in use, for clause GC; growing the local stack
include("pl-alloc.jl")         # swipl-devel src/pl-alloc.c — raising a stack overflow; the argument stack
include("pl-wam.jl")           # swipl-devel src/pl-wam.c — the local stack's operations; the query API and the run loop
include("pl-fli.jl")           # swipl-devel src/pl-fli.c — term references; raising an exception
include("pl-error.jl")         # swipl-devel src/pl-error.c — error terms (the occurs-check error)
include("pl-gmp.jl")           # swipl-devel src/pl-gmp.c — numbers: read, written, promoted, compared
include("pl-arith.jl")         # swipl-devel src/pl-arith.c — evaluation, is/2, the comparisons
include("pl-setup.jl")         # swipl-devel src/pl-setup.c — emptying the stacks of a new LD
include("pl-proc.jl")          # swipl-devel src/pl-proc.c — predicates, assert, retract, clause GC
include("pl-supervisor.jl")    # swipl-devel src/pl-supervisor.c — the code a call enters first
include("pl-trace.jl")         # swipl-devel src/pl-trace.c — prolog_current_frame/1, prolog_current_choice/1
include("pl-op.jl")            # swipl-devel src/pl-op.c — the operator tables, op/3
include("pl-ext.jl")           # swipl-devel src/pl-ext.c — registering the built-ins; their dispatch
include("precompile_workload.jl")  # ORIGINAL — the hot paths, compiled at precompile time (LAST)

# ── exports ─────────────────────────────────────────────────────────────────────────────────────
# the term interface (src/term_interface.jl)
export Kind, VAR, SYM, GND, EXPR
export kind, term_type,
    nchildren, child, sym_key, sym_hash, var_key, gnd_key, gnd_equal, atomic_compare
export mk_var, mk_expr, is_ground, is_ground_walk, KERNEL_VAR_BASE
# …and its Prolog layer (Q1): symbols, grounded values, reserved symbols, numbers by kind
export mk_sym, mk_gnd, mk_reserved_symbol, is_reserved_symbol, mk_nil, is_nil, is_pair
export sym_text
export NumKind, NUM_NONE, NUM_INTEGER, NUM_RATIONAL, NUM_FLOAT, NUM_STRING, NUM_OTHER
export number_kind,
    integer_is_int64, int64_value, bigint_value, rational_value, float_value,
    string_value
# the standard order of terms — SWI-Prolog's name (src/pl-prims.jl) — and the leaf comparisons an
# implementation's `atomic_compare` is built from (it alone can see names and values)
export compareStandard
export compareAtoms, compareStrings, compare_neq_floats, compare_mixed_float_rational
export compareReservedSymbol
# the default term type (src/default_term.jl)
export Term, DefaultTerm, sym_term, gnd_term, var_term, gnd_value_key, sym_name, gnd_value

end # module LogicKernel
