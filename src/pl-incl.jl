# UPSTREAM: swipl-devel src/pl-incl.h @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-data.h @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2026, University of Amsterdam,
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# THE SHARED DECLARATIONS the clause store and its indexes are built from: SWI-Prolog's structs
# `arg_info`, `clause`, `clause_ref`, `clause_bucket`, `clause_index`, `clause_list`, `definition`
# and `clause_choice`, with their field names, and the constants and word layout they use.
#
# How C maps to Julia here:
#   * A C pointer typedef (`ClauseIndex`, `ClauseRef`, …) is the mutable struct itself — Julia
#     structs are references. A NULL pointer is `nothing`.
#   * Structs that point at each other are parameterised to break the cycle, and the aliases at
#     the end (`ClauseRef{T}`, `ClauseIndex{T}`, …) close it again for a term type `T`; each alias
#     is a concrete type.
#   * A NULL-terminated array of indexes is a `Vector`; a `DEAD_INDEX` slot in it is `nothing`.
#   * Bit-fields are plain fields; upstream masks them explicitly where it assigns them, and so
#     does the port.

# ── scalar types ────────────────────────────────────────────────────────────────────────────────
# PORT: pl-incl.h word
"A machine word — an index key (pl-incl.h `word`)."
const word = UInt64
# PORT: pl-incl.h iarg_t
"An index argument position (pl-incl.h `iarg_t`)."
const iarg_t = UInt8
# PORT: pl-incl.h gen_t
"A logical-update generation (pl-incl.h `gen_t`)."
const gen_t = UInt64
# PORT: pl-incl.h code
"A VM code word: an instruction or one of its operands (pl-incl.h `code`)."
const code = UInt64

# PORT: pl-incl.h Code
# DIVERGES: a pointer into a code array is the array and a 1-based index into it.
"A position in VM code (pl-incl.h `Code`, a `code*`): `codes[pc]` is the word it points at."
struct Code
    codes::Vector{code}
    pc::Int
end

# ── generations, insertion points, clause and predicate flags ───────────────────────────────────
# PORT: pl-incl.h GEN_TRANSACTION_BASE
"First generation of the transaction range (pl-incl.h)."
const GEN_TRANSACTION_BASE = 0x8000000000000000
# PORT: pl-incl.h GEN_MAX
"The largest global generation; a live clause's `generation_erased` (pl-incl.h)."
const GEN_MAX = GEN_TRANSACTION_BASE - 1
# PORT: pl-incl.h CL_START
"Insertion point: the start of the clause list — `asserta` (pl-incl.h)."
const CL_START = 1
# PORT: pl-incl.h CL_END
"Insertion point: the end of the clause list — `assertz` (pl-incl.h)."
const CL_END = 2
# PORT: pl-incl.h CL_ERASED
"Clause flag: the clause was erased (pl-incl.h)."
const CL_ERASED = UInt32(0x0001)
# PORT: pl-incl.h UNIT_CLAUSE
"Clause flag: the clause has no body (pl-incl.h)."
const UNIT_CLAUSE = UInt32(0x0002)
# PORT: pl-incl.h FLAG64
"Predicate flag bit `i`, 1-based (pl-incl.h `FLAG64`)."
FLAG64(i::Int)::UInt64 = UInt64(1) << (i - 1)
# PORT: pl-incl.h P_SHRUNKPOW2
"Predicate flag: shrunk below a power of two — see `reconsider_index!` (pl-incl.h)."
const P_SHRUNKPOW2 = FLAG64(5)
# PORT: pl-incl.h P_FOREIGN
"Predicate flag: implemented in C (pl-incl.h)."
const P_FOREIGN = FLAG64(6)
# PORT: pl-incl.h P_DYNAMIC
"Predicate flag: dynamic predicate (pl-incl.h)."
const P_DYNAMIC = FLAG64(10)
# PORT: pl-incl.h P_THREAD_LOCAL
"Predicate flag: thread-local predicate (pl-incl.h)."
const P_THREAD_LOCAL = FLAG64(11)
# PORT: pl-incl.h P_MULTIFILE
"Predicate flag: clauses are in multiple files (pl-incl.h)."
const P_MULTIFILE = FLAG64(15)
# PORT: pl-incl.h P_DIRTYREG
"Predicate flag: registered as dirty (pl-incl.h)."
const P_DIRTYREG = FLAG64(23)
# PORT: pl-incl.h P_MODIFIED
"Predicate flag: the clause list is modified (pl-incl.h)."
const P_MODIFIED = FLAG64(36)
# PORT: pl-incl.h P_RELOADING
"Predicate flag: being reloaded (pl-incl.h — an alias of `P_MODIFIED`)."
const P_RELOADING = P_MODIFIED
# PORT: pl-incl.h MA_VAR
"Meta-argument specifier `-`: the argument is unbound on entry (pl-incl.h)."
const MA_VAR = UInt8(11)

# ── index limits ────────────────────────────────────────────────────────────────────────────────
# PORT: pl-incl.h MAX_MULTI_INDEX
"Most arguments one index combines (pl-incl.h)."
const MAX_MULTI_INDEX = 4
# PORT: pl-incl.h MAXINDEXARG
"Highest argument position considered for indexing (pl-incl.h)."
const MAXINDEXARG = 254
# PORT: pl-incl.h MAXINDEXDEPTH
"Deepest nesting of a deep index (pl-incl.h)."
const MAXINDEXDEPTH = 7
# PORT: pl-incl.h END_INDEX_POS
"Terminates a deep-index position path (pl-incl.h)."
const END_INDEX_POS = 0xff

# ── the word layout of index keys (pl-data.h, pl-incl.h) ────────────────────────────────────────
# Keys are words laid out as SWI lays out atoms and functors, so `isFunctor` tells a functor key
# from every other key exactly as upstream does (see `indexOfWord` in src/pl-index.jl).
# PORT: pl-data.h LMASK_BITS
"Total number of tag + storage bits in a word (pl-data.h)."
const LMASK_BITS = 7
# PORT: pl-data.h TAG_MASK
"Mask of the tag bits (pl-data.h)."
const TAG_MASK = UInt64(0x00000007)
# PORT: pl-data.h TAG_ATOM
"Tag of an atom — and, with `STG_GLOBAL`, of a functor (pl-data.h)."
const TAG_ATOM = UInt64(0x00000005)
# PORT: pl-data.h STG_MASK
"Mask of the storage bits (pl-data.h)."
const STG_MASK = UInt64(0x3) << 3
# PORT: pl-data.h STG_STATIC
"Storage: static (pl-data.h)."
const STG_STATIC = UInt64(0x0) << 3
# PORT: pl-data.h STG_GLOBAL
"Storage: global stack; with `TAG_ATOM` it marks a functor (pl-data.h)."
const STG_GLOBAL = UInt64(0x1) << 3
# PORT: pl-data.h F_ARITY_BITS
"Bits of a functor word holding an inline arity (pl-data.h)."
const F_ARITY_BITS = 5
# PORT: pl-data.h F_ARITY_MASK
"Mask of the inline arity (pl-data.h)."
const F_ARITY_MASK = UInt64((1 << F_ARITY_BITS) - 1)
# PORT: pl-data.h tagex
"The tag and storage bits of `w` (pl-data.h)."
tagex(w::word)::word = w & (TAG_MASK | STG_MASK)
# PORT: pl-data.h isFunctor
"True when the key `w` is a functor (pl-data.h)."
isFunctor(w::word)::Bool = tagex(w) == (TAG_ATOM | STG_GLOBAL)
# PORT: pl-incl.h MK_ATOM
"The atom word of atom number `n` (pl-incl.h)."
MK_ATOM(n::UInt64)::word = (n << 7) | TAG_ATOM | STG_STATIC
# PORT: pl-data.h MK_FUNCTOR
"The functor word of functor number `n` with arity `a` (pl-data.h)."
MK_FUNCTOR(n::UInt64, a::UInt64)::word =
    (((n << F_ARITY_BITS) | a) << LMASK_BITS) | TAG_ATOM | STG_GLOBAL

# ── the structs ─────────────────────────────────────────────────────────────────────────────────
# PORT: pl-incl.h arg_info
"Per-argument indexing information of a clause list (pl-incl.h `arg_info`)."
mutable struct arg_info
    speedup::Float32        # Computed speedup
    list::Bool              # Index using lists
    ln_buckets::UInt8       # lg2(bucket count) (max 4G buckets) — a 5-bit field upstream
    assessed::Bool          # Value was assessed
    meta::UInt8             # Meta-argument info
end
arg_info() = arg_info(0.0f0, false, 0x00, false, 0x00)

# PORT: pl-incl.h clause
# DIVERGES: besides its VM code the clause keeps its head TERM, which the caller unifies against
# until the VM itself is ported (upstream decompiles the code instead). D is the predicate's type —
# `definition{T}` — a parameter only to break the struct cycle.
"A clause (pl-incl.h `struct clause`): its predicate, generations, flags, VM code and head term."
mutable struct clause{T, D}
    predicate::D                    # Predicate I belong to
    generation_created::gen_t       # generation.created
    generation_erased::gen_t        # generation.erased
    flags::UInt32                   # Flag field holding CL_* flags
    codes::Vector{code}             # VM codes of clause
    head::T                         # the head term the codes were compiled from
end

# PORT: pl-incl.h clause_ref
"""
A cell in a clause chain (pl-incl.h `struct clause_ref`). `key` is upstream's `d.key`. The value
is EITHER one clause (`clause`) OR — in a list index — a clause list (`clauses`), as upstream's
`value` union is.
"""
mutable struct clause_ref{C, L}
    next::Union{Nothing, clause_ref{C, L}}  # Next in list
    key::word                               # d.key — Index key
    clause::Union{Nothing, C}               # value.clause — Single clause value
    clauses::Union{Nothing, L}              # value.clauses — Clause list (in hash-tables)
end

# PORT: pl-incl.h clause_bucket
"A bucket of a clause index (pl-incl.h `struct clause_bucket`)."
mutable struct clause_bucket{R}
    head::Union{Nothing, R}     # Head of clause list
    tail::Union{Nothing, R}     # Tail of clause list
    key::word                   # Unrestricted key if no collisions
    dirty::UInt32               # # of garbage clauses
end
clause_bucket{R}() where {R} = clause_bucket{R}(nothing, nothing, word(0), UInt32(0))

# PORT: pl-incl.h clause_index
"A hash index over one or more arguments (pl-incl.h `struct clause_index`)."
mutable struct clause_index{R}
    buckets::UInt32                                 # # entries
    size::UInt32                                    # # clauses
    resize_above::UInt32                            # consider resize > #clauses
    resize_below::UInt32                            # consider resize < #clauses
    dirty::UInt32                                   # # chains that are dirty
    is_list::Bool                                   # Index with lists
    incomplete::Bool                                # Index is incomplete
    invalid::Bool                                   # Index is invalid
    good::Bool                                      # Index is (near) perfect
    args::NTuple{MAX_MULTI_INDEX, iarg_t}           # Indexed arguments
    position::NTuple{MAXINDEXDEPTH + 1, iarg_t}     # Deep index position
    speedup::Float32                                # Estimated speedup
    entries::Union{Nothing, Vector{clause_bucket{R}}}   # chains holding the clauses
end

# PORT: pl-incl.h clause_list
"The clauses of a predicate — or of one key of a list index — with their indexes (pl-incl.h)."
mutable struct clause_list{C}
    args::Union{Nothing, Vector{arg_info}}                  # Meta and indexing info
    first_clause::Union{Nothing, clause_ref{C, clause_list{C}}}     # clause list of procedure
    last_clause::Union{Nothing, clause_ref{C, clause_list{C}}}      # last clause of list
    clause_indexes::Union{
        Nothing, Vector{Union{Nothing, clause_index{clause_ref{C, clause_list{C}}}}}
    }                                                       # Hash index(es)
    number_of_clauses::UInt32                               # number of associated clauses
    erased_clauses::UInt                                    # number of erased clauses in set
    number_of_rules::UInt32                                 # number of real rules
    unindexed::Bool                                         # no index possible
    fixed_indexes::Bool                                     # Do not search for alternatives
    pindex_verified::Bool                                   # Primary index is verified
    jiti_tried::iarg_t                                      # number of times we tried to find
    primary_index::iarg_t                                   # Index used to link clauses
end
clause_list{C}() where {C} = clause_list{C}(
    nothing, nothing, nothing, nothing, UInt32(0), UInt(0), UInt32(0), false, false,
    false,
    0x00, 0x00
)

# PORT: pl-incl.h definition
# DIVERGES: `functor` (a pointer into SWI's functor table) is its two parts here — the name's
# `sym_key` and the arity — as there is no functor table; `impl` holds only the `clauses` member
# of upstream's union (the other members are foreign, wrapped and thread-local predicates).
"A predicate (pl-incl.h `struct definition`)."
mutable struct definition{T}
    functor_name::UInt64                                    # functor->name, as a sym_key
    arity::Int                                              # functor->arity
    impl_clauses::clause_list{clause{T, definition{T}}}     # impl.clauses
    flags::UInt64                                           # booleans (P_*)
end

# PORT: pl-incl.h clause_choice
"Where a clause search resumes (pl-incl.h `struct clause_choice`)."
mutable struct clause_choice{R}
    cref::Union{Nothing, R}     # Next clause reference
    key::word                   # Search key
end

# ── the pointer typedefs, closed over a term type `T` (pl-incl.h) ───────────────────────────────
# PORT: pl-incl.h Clause
"A clause of terms `T` (pl-incl.h `Clause`)."
const Clause{T} = clause{T, definition{T}}
# PORT: pl-incl.h ClauseList
"A clause list of terms `T` (pl-incl.h `ClauseList`)."
const ClauseList{T} = clause_list{Clause{T}}
# PORT: pl-incl.h ClauseRef
"A clause reference of terms `T` (pl-incl.h `ClauseRef`)."
const ClauseRef{T} = clause_ref{Clause{T}, ClauseList{T}}
# PORT: pl-incl.h ClauseBucket
"A clause-index bucket of terms `T` (pl-incl.h `ClauseBucket`)."
const ClauseBucket{T} = clause_bucket{ClauseRef{T}}
# PORT: pl-incl.h ClauseIndex
"A clause index of terms `T` (pl-incl.h `ClauseIndex`)."
const ClauseIndex{T} = clause_index{ClauseRef{T}}
# PORT: pl-incl.h Definition
"A predicate of terms `T` (pl-incl.h `Definition`)."
const Definition{T} = definition{T}
# PORT: pl-incl.h ClauseChoice
"A clause choice of terms `T` (pl-incl.h `ClauseChoice`)."
const ClauseChoice{T} = clause_choice{ClauseRef{T}}

# ── clause garbage collection: dirty predicates and predicate access (pl-incl.h) ────────────────
# PORT: pl-incl.h GLOBALLY_VISIBLE_CLAUSE
"True when clause `cl` is visible in generation `gen`, ignoring transactions (pl-incl.h)."
GLOBALLY_VISIBLE_CLAUSE(cl::clause, gen::gen_t)::Bool =
    cl.generation_created <= gen && cl.generation_erased > gen

# PORT: pl-incl.h PROC_DIRTY_GENS
"How many access generations a dirty predicate records before it keeps an interval (pl-incl.h)."
const PROC_DIRTY_GENS = 10
# PORT: pl-incl.h DDI_MARKING
"Dirty-definition flag: clause GC is actively using the record (pl-incl.h)."
const DDI_MARKING = UInt16(0x0001)
# PORT: pl-incl.h DDI_INTERVALS
"Dirty-definition flag: the record collects an interval, not single generations (pl-incl.h)."
const DDI_INTERVALS = UInt16(0x0002)

# PORT: pl-incl.h dirty_def_info
# DIVERGES: `access` is a vector of PROC_DIRTY_GENS generations rather than an inline array.
"""
A predicate with erased clauses, and the generations it is accessed in while clause GC runs
(pl-incl.h `struct dirty_def_info`).
"""
mutable struct dirty_def_info{T}
    count::UInt16                       # # captured generations
    flags::UInt16                       # DDI_*
    predicate::Definition{T}            # The dirty predicate
    access::Vector{gen_t}               # Accessed generations
end

# PORT: pl-incl.h definition_ref
"A predicate referenced at a generation by an ongoing enumeration (pl-incl.h `definition_ref`)."
struct definition_ref{T}
    predicate::Definition{T}            # Referenced definition
    generation::gen_t                   # at generation
end
