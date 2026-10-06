# UPSTREAM: swipl-devel src/pl-incl.h @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-data.h @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-global.h @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-builtin.h @ bae881a24a3f
# UPSTREAM: swipl-devel src/SWI-Prolog.h @ bae881a24a3f
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
# PORT: pl-incl.h clsize_t
"A count of variables (frame slots) in a clause (pl-incl.h `clsize_t`)."
const clsize_t = UInt32

# PORT: pl-incl.h Code
# DIVERGES: a pointer into a code array is the array and a 1-based index into it — and the clause's
# LITERAL TABLE travels with it (decision 2, V1 L2): where upstream's operand IS an atom, a functor
# or an inline number, the kernel's operand is an index into `literals` (src/pl-comp.jl § literals),
# so whatever reads code — `argKey`, the decompiler — reads the literal through the position.
"""
A position in VM code (pl-incl.h `Code`, a `code*`): `codes[pc]` is the word it points at, and
`literals` the table its literal operands index.
"""
struct Code{T}
    codes::Vector{code}
    literals::Vector{T}
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
# PORT: pl-incl.h COMMIT_CLAUSE
"Clause flag: the clause will commit — its body starts with `!` (pl-incl.h)."
const COMMIT_CLAUSE = UInt32(0x0010)
# PORT: pl-incl.h FLAG64
"Predicate flag bit `i`, 1-based (pl-incl.h `FLAG64`)."
FLAG64(i::Int)::UInt64 = UInt64(1) << (i - 1)
# PORT: pl-incl.h P_SHRUNKPOW2
"Predicate flag: shrunk below a power of two — see `reconsider_index!` (pl-incl.h)."
const P_SHRUNKPOW2 = FLAG64(5)
# PORT: pl-incl.h P_FOREIGN
"Predicate flag: implemented in C (pl-incl.h)."
const P_FOREIGN = FLAG64(6)
# PORT: pl-incl.h P_NONDET
"Predicate flag: a non-deterministic foreign predicate (pl-incl.h)."
const P_NONDET = FLAG64(7)
# PORT: pl-incl.h P_VARARG
"Predicate flag: a foreign predicate called with `t0, ac, ctx` (pl-incl.h)."
const P_VARARG = FLAG64(8)
# PORT: pl-incl.h P_FOREIGN_CREF
"Predicate flag: a foreign predicate whose non-deterministic context is a clause (pl-incl.h)."
const P_FOREIGN_CREF = FLAG64(9)
# PORT: pl-incl.h P_DYNAMIC
"Predicate flag: dynamic predicate (pl-incl.h)."
const P_DYNAMIC = FLAG64(10)
# PORT: pl-incl.h P_THREAD_LOCAL
"Predicate flag: thread-local predicate (pl-incl.h)."
const P_THREAD_LOCAL = FLAG64(11)
# PORT: pl-incl.h P_DISCONTIGUOUS
"Predicate flag: clauses are not together (pl-incl.h)."
const P_DISCONTIGUOUS = FLAG64(14)
# PORT: pl-incl.h P_MULTIFILE
"Predicate flag: clauses are in multiple files (pl-incl.h)."
const P_MULTIFILE = FLAG64(15)
# PORT: pl-incl.h P_ISO
"Predicate flag: part of the ISO standard (pl-incl.h)."
const P_ISO = FLAG64(17)
# PORT: pl-incl.h P_LOCKED
"Predicate flag: locked as a system predicate (pl-incl.h)."
const P_LOCKED = FLAG64(18)
# PORT: pl-incl.h P_TRANSPARENT
"Predicate flag: inherits the calling module (pl-incl.h)."
const P_TRANSPARENT = FLAG64(20)
# PORT: pl-incl.h P_DIRTYREG
"Predicate flag: registered as dirty (pl-incl.h)."
const P_DIRTYREG = FLAG64(23)
# PORT: pl-incl.h HIDE_CHILDS
"Predicate flag: hide the children from the tracer (pl-incl.h; set on built-ins, read only by the debugger)."
const HIDE_CHILDS = FLAG64(25)
# PORT: pl-incl.h TRACE_ME
"Predicate flag: can be debugged (pl-incl.h; the debugger's, never set here — see `registerBuiltins!`)."
const TRACE_ME = FLAG64(27)
# PORT: pl-incl.h P_LOCKED_SUPERVISOR
"Predicate flag: fixed supervisor (pl-incl.h)."
const P_LOCKED_SUPERVISOR = FLAG64(31)
# PORT: pl-incl.h P_REDEFINED
"Predicate flag: overrules a definition (pl-incl.h)."
const P_REDEFINED = FLAG64(33)
# PORT: pl-incl.h P_SIG_ATOMIC
"Predicate flag: do not call handleSignals (pl-incl.h)."
const P_SIG_ATOMIC = FLAG64(34)
# PORT: pl-incl.h P_TRANSACT
"Predicate flag: subject to transactions (pl-incl.h)."
const P_TRANSACT = FLAG64(35)
# PORT: pl-incl.h PROC_DEFINED
"The predicate flags that make a predicate defined without clauses (pl-incl.h)."
const PROC_DEFINED =
    P_DYNAMIC | P_FOREIGN | P_MULTIFILE | P_DISCONTIGUOUS | P_LOCKED_SUPERVISOR
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
# PORT: pl-data.h TAG_VAR
"Tag of a variable (pl-data.h)."
const TAG_VAR = UInt64(0x00000000)
# PORT: pl-data.h TAG_ATOM
"Tag of an atom — and, with `STG_GLOBAL`, of a functor (pl-data.h)."
const TAG_ATOM = UInt64(0x00000005)
# PORT: pl-data.h MARK_MASK
"The GC mark bit (pl-data.h); variant_sha1 sets it in the words it numbers variables with."
const MARK_MASK = UInt64(0x1) << 5
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
# PORT: pl-incl.h PLMINTAGGEDINT
"The smallest integer a word holds tagged — inline, `STG_INLINE` (pl-incl.h; 64-bit words)."
const PLMINTAGGEDINT = -(Int64(1) << (64 - LMASK_BITS - 1))
# PORT: pl-incl.h PLMAXTAGGEDINT
"The largest integer a word holds tagged (pl-incl.h)."
const PLMAXTAGGEDINT = -PLMINTAGGEDINT - 1
# PORT: pl-incl.h PLMINTAGGEDINT32
"The smallest integer a 32-bit word holds tagged (pl-incl.h)."
const PLMINTAGGEDINT32 = -(Int64(1) << (32 - LMASK_BITS - 1))
# PORT: pl-incl.h PLMAXTAGGEDINT32
"The largest integer a 32-bit word holds tagged (pl-incl.h); `variant_hash/2` masks with it."
const PLMAXTAGGEDINT32 = -PLMINTAGGEDINT32 - 1

# ── unification: return codes, the occurs-check flag, backtrack marks ──────────────────────────
# PORT: pl-incl.h boolex_t
# DIVERGES: only the codes the ported unifier, clause compiler and local stack return. The other
# stack-overflow codes are not ported: there is no global, trail or argument stack of fixed size.
"Success, failure, a stack overflow, or \"needs the compound algorithm\" (pl-incl.h `boolex_t`)."
@enum boolex_t::Int8 begin
    BOOLEX_TRUE = 1             # logical success (= `true`)
    BOOLEX_FALSE = 0            # logical failure (= `false`)
    LOCAL_OVERFLOW = -1         # Local stack overflow
    DO_COMPOUND = -8            # need more general algorithm
    NOT_CALLABLE = -9           # pl-comp.c
    MAX_ARITY_OVERFLOW = -10    # pl-comp.c
end

# PORT: pl-incl.h occurs_check_t
"The `occurs_check` Prolog flag (pl-incl.h `occurs_check_t`); SWI's default is `OCCURS_CHECK_FALSE`."
@enum occurs_check_t::UInt8 begin
    OCCURS_CHECK_FALSE = 0      # allow rational trees
    OCCURS_CHECK_TRUE           # fail if rational tree would result
    OCCURS_CHECK_ERROR          # exception if rational tree would result
end

# PORT: pl-incl.h mark
# DIVERGES: only `trailtop`. Bindings live in a store, not on a global stack, so there is no
# `globaltop` to reset, and no `saved_bar` (`LD->mark_bar` decides which assignments need trailing;
# every binding is trailed here).
"A backtrack mark (pl-incl.h `struct mark`): the height of the trail when it was taken."
struct mark
    trailtop::Int               # top of the trail stack
end

# PORT: pl-incl.h NOT_A_MARK
"The `trailtop` of a mark that must never be undone to (pl-incl.h; `~(word)0` as a trail height)."
const NOT_A_MARK = -1

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

# PORT: pl-incl.h procedure
# DIVERGES: no `source_no` (source files are not ported). D is the predicate's type —
# `definition{T}` — a parameter only to break the struct cycle with `clause`.
"A procedure (pl-incl.h `struct procedure`): the predicate a functor names in a module."
mutable struct procedure{D}
    definition::D           # definition of procedure
    flags::UInt32           # PROC_WEAK
end

# PORT: pl-incl.h clause
# DIVERGES: besides its VM code the clause keeps its LITERAL TABLE (`literals`, decision 2, V1 L2):
# the terms its literal operands index, each exactly as it stood in the clause — upstream's operands
# hold the atom, functor or number itself — and its PROCEDURE TABLE (`procedures`, V1): the
# procedures its call operands (`I_CALL`, `I_DEPART`, …) index, where upstream's operand is the
# `Procedure` pointer itself (user, 2026-10-04: decoding stays local to the clause, as with the
# literals). No source-file fields (`line_no`, `source_no`, `owner_no`), no `references` (no
# reference-counted clause references) and no `tr_erased_no` (transactions); `code_size` is the
# length of `codes`. D is the predicate's type — `definition{T}` — a parameter only to break the
# struct cycle.
"""
A clause (pl-incl.h `struct clause`): its predicate, generations, frame size, flags, VM code, and
the literals and procedures that code refers to.
"""
mutable struct clause{T, D}
    predicate::D                    # Predicate I belong to
    generation_created::gen_t       # generation.created
    generation_erased::gen_t        # generation.erased
    variables::clsize_t             # # of variables for frame
    prolog_vars::clsize_t           # # real Prolog variables
    flags::UInt32                   # Flag field holding CL_* flags
    codes::Vector{code}             # VM codes of clause
    literals::Vector{T}             # the terms the codes' literal operands index
    procedures::Vector{procedure{D}}    # the procedures the codes' call operands index
end

"The start of `cl`'s code (upstream's `PC = cl->codes`), with its literal table."
Code(cl::clause{T}, pc::Int) where {T} = Code{T}(cl.codes, cl.literals, pc)

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

# PORT: pl-global.h PL_code_data
# DIVERGES: the shared supervisors only (`supervisors`, built by `initSupervisors`), and ONE PER
# DATABASE where upstream has one per process: the kernel has no module-level mutable state. A
# definition and its module reach their database's copy (`code_data`). A shared block is known by its
# identity, where upstream reads a length word of 0 before it; each is upstream's `[I, I_EXIT]`.
"The shared supervisor code blocks of a database (pl-global.h `PL_code_data.supervisors`)."
struct PL_code_data
    exit::Vector{code}          # I_EXIT
    virgin::Vector{code}        # S_VIRGIN
    undef::Vector{code}         # S_UNDEF
    dynamic::Vector{code}       # S_DYNAMIC
    multifile::Vector{code}     # S_MULTIFILE
    staticp::Vector{code}       # S_STATIC
end

# PORT: pl-incl.h definition
# DIVERGES: `functor` (a pointer into SWI's functor table) is its parts here — the name's `sym_key`,
# the arity, and the name itself (`name`, the symbol: an error term names the predicate) — as there
# is no functor table; `impl` holds the `clauses` member of upstream's union and, since V5a2, its
# `foreign.function` as `impl_foreign_function`, the built-in's index in the dispatch table
# (decision 5: "the operand is the table index"; src/pl-ext.jl) — two fields, as Julia has no union
# of a clause list and an integer; the wrapped and thread-local members are not ported. `codes`, the supervisor, keeps its
# clause-reference operands in a side table, `codes_crefs`, as a clause's code keeps its literals:
# the operand is an index into it. `code_data` reaches the database's shared supervisors.
"A predicate (pl-incl.h `struct definition`)."
mutable struct definition{T}
    functor_name::UInt64                                    # functor->name, as a sym_key
    arity::Int                                              # functor->arity
    impl_clauses::clause_list{clause{T, definition{T}}}     # impl.clauses
    flags::UInt64                                           # booleans (P_*)
    const name::T                                           # functor->name, the symbol
    codes::Vector{code}                                     # Executable code
    codes_crefs::Vector{
        clause_ref{clause{T, definition{T}}, clause_list{clause{T, definition{T}}}}
    }
    const code_data::PL_code_data                           # PL_code_data (the database's)
    impl_foreign_function::Int                              # impl.foreign.function (0: none)
end

# PORT: pl-incl.h module as module_t
# DIVERGES: a module's name and its procedure table only — no source file, public list,
# operators, super modules, lingering definitions, code size or flags. The kernel has ONE module
# per database, `user` (see `MODULE_user`, src/pl-global.jl): modules are not ported. The table is
# keyed by the FUNCTOR — upstream's `functor_t`, here the name's `sym_key` and the arity. Named
# `module_t` (SWI-Prolog.h's own name for a module): `module` is a Julia keyword and `Module` Core's.
# `code_data` (no upstream field) is the database's shared supervisors, which a new procedure starts
# with (`SUPERVISOR(virgin)`).
"A module (pl-incl.h `struct module`): its name and the procedures defined in it."
struct module_t{T}
    name::UInt64                                                # name of module, as a sym_key
    procedures::Dict{Tuple{UInt64, Int}, procedure{definition{T}}}  # predicates of the module
    code_data::PL_code_data                                     # the database's shared supervisors
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
# PORT: pl-incl.h Procedure
"A procedure of terms `T` (pl-incl.h `Procedure`)."
const Procedure{T} = procedure{definition{T}}

# ── the local stack: positions, frames, choice points, foreign frames (pl-incl.h; decision 3) ───
#
# ONE POSITION SPACE, as upstream has one local stack. A position is a word offset from `lBase`
# (`consTermRef`), from 0, so a position is also a `term_t` and a `fid_t`. The local stack's CELLS
# are `LD.slots` (position `p` is `slots[p + 1]`). A frame, a choice point or a foreign frame is a
# RECORD in LD's pool for its kind. The record holds its `base`, the position where upstream's struct
# starts, and it spans as many positions as upstream's struct has words. So every position is
# swipl's own (user, 2026-10-05): the differences between them that `prolog_current_frame/1` and
# `prolog_current_choice/1` report are the oracle for frame placement, reuse and popping. A record's
# fields live in the record; the slots of its header positions are never read.
#
# DIVERGES from this file's rule above: a `LocalFrame`, `Choice` or `FliFrame` pointer is an INDEX
# into its pool (0 = NULL), not a reference. A record is then known, as upstream knows it, by its
# place on the stack: every age test upstream makes by address compares `base` positions. The
# records are mutable and preallocated, reused per index (user, 2026-10-05). Upstream writes their
# fields one at a time, and growing the stack stays the only allocating path.

# The sizes of upstream's structs in words, in the default x86_64 Linux build: `O_PROFILE` is on
# there, so `prof_node` counts although the kernel keeps no profiler, and `O_DEBUG` is off. They are
# derived from the structs (pl-incl.h:1770-1784, 1824-1836, 1938-1946). swipl 10.1.16 agrees on the
# frame: `p(A) :- …, q(A, _, _)` puts `q`'s frame 8 + 2 positions above `p`'s (`A` and the frame
# variable; the voids take no slot).
"`sizeof(struct localFrame)` in words: the positions a frame's header spans."
const SIZEOF_LOCALFRAME = 8
"`sizeof(struct choice)` in words: the positions a choice point spans."
const SIZEOF_CHOICE = 9
"`sizeof(struct fliFrame)` in words: the positions a foreign frame's header spans."
const SIZEOF_FLIFRAME = 6

# PORT: pl-incl.h ARGOFFSET
# DIVERGES: in positions (words), where upstream's is in bytes.
"Where a frame's arguments start, from its base (pl-incl.h): the size of its header."
const ARGOFFSET = SIZEOF_LOCALFRAME

# PORT: pl-incl.h VAROFFSET
"The frame offset of variable slot `var` (pl-incl.h): the header, then the slots."
VAROFFSET(var::Int)::code = code(var + ARGOFFSET)

# PORT: pl-incl.h VARNUM
"The variable slot of frame offset `i` (pl-incl.h); the inverse of `VAROFFSET`."
VARNUM(i::code)::Int = Int(i) - ARGOFFSET

# PORT: pl-incl.h MAXARITY
"The largest arity of a predicate (pl-incl.h)."
const MAXARITY = 1024

# PORT: pl-incl.h MINFOREIGNSIZE
"The term references a new foreign frame has room for at least (pl-incl.h)."
const MINFOREIGNSIZE = 32

# PORT: pl-incl.h LOCAL_MARGIN
# DIVERGES: in positions, where upstream's is in bytes.
"The space a call keeps free above `lTop`: a frame, its arguments and one choice point (pl-incl.h)."
const LOCAL_MARGIN = SIZEOF_LOCALFRAME + MAXARITY + SIZEOF_CHOICE

# PORT: pl-incl.h ALLOW_SHIFT
"`growLocalSpace` may grow the stacks (pl-incl.h)."
const ALLOW_SHIFT = 2

# PORT: pl-incl.h FR_HIDE_CHILDS
"Frame flag: the predicate's children are hidden, after `I_DEPART` (pl-incl.h)."
const FR_HIDE_CHILDS = UInt32(0x0001)
# PORT: pl-incl.h FR_SKIPPED
"Frame flag: the debugger skipped this frame (pl-incl.h)."
const FR_SKIPPED = UInt32(0x0002)
# PORT: pl-incl.h FR_MARKED
"Frame flag: marked by GC (pl-incl.h)."
const FR_MARKED = UInt32(0x0004)
# PORT: pl-incl.h FR_MARKED_PRED
"Frame flag: GC marked its predicate and clause (pl-incl.h)."
const FR_MARKED_PRED = UInt32(0x0008)
# PORT: pl-incl.h FR_NOTIFY
"Frame flag: notify its destruction, for the GUI debugger (pl-incl.h)."
const FR_NOTIFY = UInt32(0x0010)
# PORT: pl-incl.h FR_CAUGHT
"Frame flag: the frame caught an exception (pl-incl.h)."
const FR_CAUGHT = UInt32(0x0020)
# PORT: pl-incl.h FR_INBOX
"Frame flag: inside the box, for REDO in a built-in (pl-incl.h)."
const FR_INBOX = UInt32(0x0040)
# PORT: pl-incl.h FR_CONTEXT
"Frame flag: the frame's context module is set (pl-incl.h)."
const FR_CONTEXT = UInt32(0x0080)
# PORT: pl-incl.h FR_CLEANUP
"Frame flag: `setup_call_cleanup/4` (pl-incl.h)."
const FR_CLEANUP = UInt32(0x0100)
# PORT: pl-incl.h FR_INRESET
"Frame flag: continuations, inside `reset/3` (pl-incl.h)."
const FR_INRESET = UInt32(0x0200)
# PORT: pl-incl.h FR_SSU_DET
"Frame flag: demands determinism on `=>` rules (pl-incl.h)."
const FR_SSU_DET = UInt32(0x0400)
# PORT: pl-incl.h FR_DET
"Frame flag: declared det (pl-incl.h)."
const FR_DET = UInt32(0x0800)
# PORT: pl-incl.h FR_DETGUARD
"Frame flag: guarded for determinism (pl-incl.h)."
const FR_DETGUARD = UInt32(0x1000)
# PORT: pl-incl.h FR_DETGUARD_SET
"Frame flag: `FR_DETGUARD` was set on this frame (pl-incl.h)."
const FR_DETGUARD_SET = UInt32(0x2000)
# PORT: pl-incl.h FR_WATCHED
"Frame flags whose frame must be finished explicitly (pl-incl.h)."
const FR_WATCHED = FR_CLEANUP | FR_NOTIFY
# PORT: pl-incl.h FR_MAGIC_MASK
"The bits of a frame's flags that hold its magic (pl-incl.h)."
const FR_MAGIC_MASK = UInt32(0xffff0000)
# PORT: pl-incl.h FR_MAGIC_MASK2
"The bits of the magic that survive `killFrame` (pl-incl.h)."
const FR_MAGIC_MASK2 = UInt32(0xfff00000)
# PORT: pl-incl.h FR_MAGIC
"The magic in the flags of a live frame (pl-incl.h)."
const FR_MAGIC = UInt32(0xc9d50000)
# PORT: pl-incl.h FR_LCO_CLEAR
"Frame flags cleared when a frame is reused for the last call (pl-incl.h)."
const FR_LCO_CLEAR =
    FR_SKIPPED | FR_WATCHED | FR_CAUGHT | FR_HIDE_CHILDS | FR_CLEANUP | FR_SSU_DET
# PORT: pl-incl.h FR_CLEAR_NEXT
"Frame flags a child does not inherit (pl-incl.h)."
const FR_CLEAR_NEXT = FR_LCO_CLEAR | FR_DET | FR_DETGUARD
# PORT: pl-incl.h FR_CLEAR_ALWAYS
"Frame flags cleared on every new frame (pl-incl.h)."
const FR_CLEAR_ALWAYS = FR_CONTEXT | FR_DETGUARD_SET
# PORT: pl-incl.h FR_CLEAR_FLAGS
"Frame flags a new frame does not take from its parent (pl-incl.h)."
const FR_CLEAR_FLAGS = FR_CLEAR_NEXT | FR_CLEAR_ALWAYS

# PORT: pl-incl.h localFrame
# DIVERGES: a pool record (see above). `parent` is a frame index; `programPointer` is a `Code` —
# the clause's code and an index into it, as everywhere here. Not kept: `context`, the context
# module, read only for transparent predicates (`contextModule`; one module, no transparency yet)
# and `prof_node` (no profiler); both still count in `SIZEOF_LOCALFRAME`.
"A frame on the local stack (pl-incl.h `struct localFrame`)."
mutable struct localFrame{T}
    base::Int                               # its position (upstream: its address)
    programPointer::Code{T}                 # pointer into program
    parent::Int                             # parent local frame (an index; 0 = NULL)
    clause::Union{Nothing, ClauseRef{T}}    # Current clause of frame
    predicate::Union{Nothing, Definition{T}} # Predicate we are running
    generation::gen_t                       # generation of the database
    level::UInt32                           # recursion level
    flags::UInt32                           # packed long holding:
end

# PORT: pl-incl.h choice_type
"What a choice point resumes (pl-incl.h `choice_type`)."
@enum choice_type::UInt8 begin
    CHP_JUMP = 0                # A jump due to ;
    CHP_CLAUSE                  # Next clause of predicate
    CHP_TOP                     # First (toplevel) choice
    CHP_CATCH                   # $catch initiated choice
    CHP_DEBUG                   # Enable redo
end

# PORT: pl-incl.h choice
# DIVERGES: a pool record (see above); `parent` is a choice index and `frame` a frame index.
# `value.clause` is the choice's OWN `clause_choice`, created with the record and reused with it —
# where upstream embeds the struct and hands out a pointer to it (user, 2026-10-05). `newChoice`
# resets it. The union's other members arrive with their creators: `pc` with `C_OR` and `foreign`
# with non-deterministic built-ins (V9). `prof_node` is not kept (no profiler) but counts in
# `SIZEOF_CHOICE`.
"A choice point on the local stack (pl-incl.h `struct choice`)."
mutable struct choice{T}
    base::Int                               # its position (upstream: its address)
    type::choice_type                       # CHP_*
    parent::Int                             # Alternative if I fail (an index; 0 = NULL)
    mark::mark                              # data mark for undo
    frame::Int                              # Frame I am related to (an index)
    const value_clause::ClauseChoice{T}     # value.clause — Next candidate clause
end

# PORT: pl-incl.h fliFrame
# DIVERGES: a pool record (see above); `parent` is a foreign-frame index. `magic` is not kept: it
# exists under `O_DEBUG` only, and neither counts in `SIZEOF_FLIFRAME`.
"A foreign frame on the local stack (pl-incl.h `struct fliFrame`): the term references above it."
mutable struct fliFrame
    base::Int                               # its position (upstream: its address)
    size::Int                               # # slots on it
    no_free_before::Int                     # No free before this
    parent::Int                             # parent FLI frame (an index; 0 = NULL)
    mark::mark                              # data-stack mark
end

# The VM's argument pointer — upstream's `Word ARGP` register (pl-wam.c), which points at "the
# next cell" — as ONE concrete immutable value in its three forms (user, 2026-10-05), so the register,
# the argument stack and a query's saved registers have one type:
#   * ARGP_SLOT — a position on the local stack (`pos`): a frame's argument slot, or above `lTop`;
#   * ARGP_CURSOR — child `pos` of the compound `term` (read mode inside a caller's compound, where
#     upstream points into its arguments);
#   * ARGP_BUILD — cell `pos` of the write-mode builder (LD's `bcells`), where upstream points into a
#     compound it is filling on the global stack.
# `term` is meaningful for a cursor only; the other forms carry any term there.
"The VM's argument pointer (upstream's `Word ARGP`): a slot, a cursor into a compound, or a builder cell."
struct argp_t{T}
    form::UInt8
    pos::Int
    term::T
end
"`argp_t` form: a position on the local stack."
const ARGP_SLOT = 0x00
"`argp_t` form: child `pos` of the compound `term`."
const ARGP_CURSOR = 0x01
"`argp_t` form: cell `pos` of the write-mode builder."
const ARGP_BUILD = 0x02

# An argument-stack entry. Upstream pushes `(ARGP+1)|UMODE` — the mode in the pointer's low bit
# (vmi:777, 873-875); the kernel also records how many builders were open, because the `H_POP`
# that pops the entry closes the builders opened since (decision 2 and Q3: the builder is a stack).
"An argument-stack entry: the `ARGP` to resume at, whether that is in write mode, the builders open."
struct argstack_entry{T}
    argp::argp_t{T}
    uwrite::Bool
    builders::Int
end

# A compound being built in write mode (decision 2, Q3): its cells are `bcells[start:start+n-1]` —
# the children vector of the term to build: the head symbol first for `f/k` and lists, none for
# `$expr/n` — and the finished compound goes to one of three places when it is closed: the parent's
# builder cell `cell`; the frame slot at position `slot` — a body argument, written untrailed above
# `lTop` as upstream's `*ARGP = consPtr(gTop)` (V4b, user 2026-10-05: the SAME builder for bodies);
# or, when it was opened in read mode on the caller's unbound variable `var`, `var` (trailed).
# `cell` is 0 and `slot` is -1 where unused.
"A write-mode builder: its cells, and where the compound goes when it is closed."
struct bframe{T}
    start::Int
    n::Int
    cell::Int
    slot::Int
    var::T
end

# PORT: pl-incl.h StackMagic
"A magic number in upstream's stack-magic family (pl-incl.h)."
StackMagic(n::Int)::UInt = UInt(n) | UInt(0x98765000)
# PORT: pl-incl.h QID_MAGIC
"The magic of an open query frame (pl-incl.h)."
const QID_MAGIC = StackMagic(1)
# PORT: pl-incl.h QID_CMAGIC
"The magic of a closed query frame (pl-incl.h)."
const QID_CMAGIC = StackMagic(2)

# `sizeof(struct queryFrame)` in words (the default build), and where its members lie, from its base:
# confirmed against upstream's headers and live in libswipl 10.1.16 (V4a research): the CHP_TOP
# choice point at 21, `saved_environment` 30, the top frame 31, the query's frame 39, its
# arguments from 47.
"`sizeof(struct queryFrame)` in words: the positions a query frame spans before its arguments."
const SIZEOF_QUERYFRAME = 47
"Where a query frame's CHP_TOP choice point lies, from its base (`offsetof(…, choice)` in words)."
const QF_CHOICE = 21
"Where a query frame's `saved_environment` lies, from its base."
const QF_SAVED_ENVIRONMENT = 30
"Where a query frame's top frame lies, from its base."
const QF_TOP_FRAME = 31
"Where a query frame's own frame lies, from its base."
const QF_FRAME = 39

# PORT: pl-incl.h QF_PARENT_ENV_OFFSET
"The words from `saved_environment` to the top frame: `parentFrame` of a top frame reads there (pl-incl.h)."
const QF_PARENT_ENV_OFFSET = QF_TOP_FRAME - QF_SAVED_ENVIRONMENT

# PORT: pl-incl.h except_class
"How urgent an exception is (pl-incl.h `except_class`): a raise replaces a pending ball of a lower class only."
@enum except_class::UInt8 begin
    EXCEPT_NONE = 0                 # no exception
    EXCEPT_OTHER                    # any other exception
    EXCEPT_ERROR                    # ISO error(Formal,Context)
    EXCEPT_RESOURCE                 # ISO error(resource_error(_), _)
    EXCEPT_TIMEOUT                  # time_limit_exceeded
    EXCEPT_UNWIND                   # unwind(Term)
    EXCEPT_ABORT                    # unwind(abort)
    EXCEPT_THREAD_EXIT              # unwind(thread_exit(Term))
    EXCEPT_HALT                     # unwind(halt(Code)
end

# PORT: pl-builtin.h FRG_FIRST_CALL
"Foreign control: the initial call (pl-builtin.h `frg_code`)."
const FRG_FIRST_CALL = 0
# PORT: pl-builtin.h FRG_CUTTED
"Foreign control: the context was cut (pl-builtin.h `frg_code`)."
const FRG_CUTTED = 1
# PORT: pl-builtin.h FRG_REDO
"Foreign control: a normal redo (pl-builtin.h `frg_code`)."
const FRG_REDO = 2
# PORT: pl-builtin.h FRG_RESUME
"Foreign control: resume from a yield (pl-builtin.h `frg_code`)."
const FRG_RESUME = 3

# PORT: pl-builtin.h foreign_context
# DIVERGES: no `engine` — a built-in is passed `ld` (decision 5's signature), so the field that is
# upstream's way to it has no use; `predicate` is `nothing` until a call sets it. Upstream's lives in
# the run loop's C-stack register file (`FNDET_CONTEXT`); here it is a field of the QUERY record,
# which is pooled, so a call allocates none (nested queries each own one, as each C frame does).
"The control argument of a foreign predicate (pl-builtin.h `struct foreign_context`; `control_t`)."
mutable struct foreign_context{T}
    control::Int                                    # FRG_* action
    context::UInt                                   # context value
    predicate::Union{Nothing, definition{T}}        # called Prolog predicate
end
# PORT: SWI-Prolog.h control_t
"The control argument a foreign predicate receives (SWI-Prolog.h `control_t`)."
const control_t{T} = foreign_context{T}

# PORT: pl-incl.h queryFrame
# DIVERGES: a pool record (see above). Its embedded `choice`, `top_frame` and `frame` are records in
# their own pools at `base + QF_CHOICE`, `+ QF_TOP_FRAME` and `+ QF_FRAME`, held here by index, as
# are `parent`, `saved_bfr`, `saved_environment` and `next_environment`; `saved_ltop` is a position,
# `exception` a term reference, `foreign_frame` a foreign-frame handle. `aSave` is the argument
# stack's height, and `bSave`/`bcSave` the builder's (frames and cells), saved with it. `registers.pc`
# is a `Code`. Not kept, but counted in `SIZEOF_QUERYFRAME`: the depth limit (`O_LIMIT_DEPTH`; no
# depth limit), `yield` (not ported, decision 1), `debugSave` and `flags_saved` (the debugger and
# the run-mode flags, not ported), `qid` (the query is identified by its position, decision 1).
"A query on the local stack (pl-incl.h `struct queryFrame`)."
mutable struct queryFrame{T}
    base::Int                       # its position (upstream: its address)
    magic::UInt                     # Magic code for security
    registers_fr::Int               # registers.fr (an index; 0 = NULL)
    registers_argp::argp_t{T}       # registers.argp
    registers_pc::Code{T}           # registers.pc
    next_environment::Int           # See D_BREAK and get_vmi_state()
    exception::Int                  # Exception term (a term reference; 0 = none)
    foreign_frame::Int              # Frame after PL_next_solution() (a handle; 0 = none)
    flags::UInt32
    solutions::Int                  # # of solutions produced
    aSave::Int                      # saved argument-stack
    bSave::Int                      # (the builder's frames)
    bcSave::Int                     # (the builder's cells)
    saved_bfr::Int                  # Saved choice-point (an index)
    saved_ltop::Int                 # Saved lTop
    parent::Int                     # Parent queryFrame (an index)
    choice::Int                     # First (dummy) choice-point (an index)
    saved_environment::Int          # Parent local-frame (an index)
    top_frame::Int                  # The (dummy) top local frame (an index)
    frame::Int                      # The initial frame (an index)
    fndet_context::foreign_context{T}   # (the run loop's FNDET_CONTEXT; see foreign_context)
end

# PORT: pl-incl.h argFrameP
# DIVERGES: on the frame's base position, where upstream's takes the frame's address — the same
# arithmetic. A position upstream casts to a frame (`argFrameP(lTop, 0)`) is passed as is.
"The position of argument `n` of the frame at position `f` (pl-incl.h)."
argFrameP(f::Int, n::Int)::Int = f + ARGOFFSET + n

# PORT: pl-incl.h varFrameP
"The position at frame offset `n` of the frame at position `f` (pl-incl.h)."
varFrameP(f::Int, n::Int)::Int = f + n

# PORT: pl-incl.h refFliP
"The position of term reference `n` of the foreign frame at position `f` (pl-incl.h)."
refFliP(f::Int, n::Int)::Int = f + SIZEOF_FLIFRAME + n

# PORT: pl-incl.h isFrame
"Whether `fr`'s flags carry the frame magic (pl-incl.h)."
isFrame(fr::localFrame)::Bool = (fr.flags & FR_MAGIC_MASK) == FR_MAGIC

# PORT: pl-incl.h generationFrame
"The database generation frame `fr` runs in (pl-incl.h)."
generationFrame(fr::localFrame)::gen_t = fr.generation

# PORT: pl-incl.h levelFrame
"The recursion level of frame `fr` (pl-incl.h)."
levelFrame(fr::localFrame)::UInt32 = fr.level

# PORT: pl-incl.h setLevelFrame
"Set the recursion level of frame `fr` (pl-incl.h)."
function setLevelFrame(fr::localFrame, l::UInt32)::Nothing
    fr.level = l
    return nothing
end

# PORT: pl-incl.h setNextFrameFlags
"Frame `next` is a child of `fr`: one level deeper, `fr`'s flags but `FR_CLEAR_FLAGS` (pl-incl.h)."
function setNextFrameFlags(next::localFrame, fr::localFrame)::Nothing
    next.level = fr.level + UInt32(1)
    next.flags = fr.flags & ~FR_CLEAR_FLAGS
    return nothing
end

# PORT: pl-incl.h lcoSetNextFrameFlags2
"As `setNextFrameFlags`, keeping the flags a last call keeps (pl-incl.h)."
function lcoSetNextFrameFlags2(next::localFrame, fr::localFrame)::Nothing
    next.level = fr.level + UInt32(1)
    next.flags = fr.flags & ~(FR_LCO_CLEAR | FR_CLEAR_ALWAYS)
    return nothing
end

# PORT: pl-incl.h lcoSetNextFrameFlags
"Frame `fr` is reused for its last call (pl-incl.h)."
lcoSetNextFrameFlags(fr::localFrame)::Nothing = lcoSetNextFrameFlags2(fr, fr)

# PORT: pl-incl.h tcallSetNextFrameFlags
"Frame `fr` is reused in place by `I_TCALL` (pl-incl.h)."
function tcallSetNextFrameFlags(fr::localFrame)::Nothing
    fr.level = fr.level + UInt32(1)
    fr.flags = fr.flags & ~(FR_LCO_CLEAR | FR_DETGUARD_SET)
    return nothing
end

# PORT: pl-incl.h setFramePredicate
"Frame `fr` runs predicate `def` (pl-incl.h)."
function setFramePredicate(fr::localFrame{T}, def::Definition{T})::Nothing where {T}
    fr.predicate = def
    return nothing
end

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

# ── the type tests on a term (pl-data.h) ─────────────────────────────────────────────────────────
# Upstream's tests read a word's TAG; here they read the term interface's kinds (invariant 8: never
# a Julia type). Each takes a DEREFERENCED term, as upstream's take a word. A kernel-only grounded
# value (`NUM_OTHER`) is a non-text blob, as it sorts (`OTHER_BLOB_RANK`): atomic, and no other
# type; a compound with a non-symbol head (`$expr/n`) is a compound.

# PORT: pl-data.h canBind
# DIVERGES: no attributed variables, so an unbound variable is all that can bind.
"Whether `t` can be bound (pl-data.h `canBind`): an unbound variable."
canBind(t)::Bool = kind(t) === VAR

# PORT: pl-data.h isAtom
# DIVERGES: an atom is a symbol — text or reserved (`[]`) — or a kernel-only value (`NUM_OTHER`), a
# non-text blob, which SWI holds as an atom (`H_ATOM` compiles it so: see `addLiteral!`).
"Whether `t` is an atom (pl-data.h `isAtom`): a symbol, or a non-text blob."
isAtom(t)::Bool = kind(t) === SYM || number_kind(t) === NUM_OTHER

# PORT: pl-data.h isTaggedInt
# DIVERGES: no words: an `Int64` within the tagged range is what a tagged word holds; a larger one is
# an indirect, a big integer.
"Whether `t` is an integer held in a tagged word (pl-data.h `isTaggedInt`): the tagged range."
isTaggedInt(t)::Bool =
    number_kind(t) === NUM_INTEGER && integer_is_int64(t) &&
    PLMINTAGGEDINT <= int64_value(t) <= PLMAXTAGGEDINT

# PORT: pl-data.h isTextAtom
"Whether `t` is a text atom (pl-data.h `isTextAtom`): a symbol, not a reserved one such as `[]`."
isTextAtom(t)::Bool = kind(t) === SYM && !is_reserved_symbol(t)

# PORT: pl-data.h isRational
"Whether `t` is a rational number (pl-data.h `isRational`): an integer or a rational."
isRational(t)::Bool = (k=number_kind(t); k === NUM_INTEGER || k === NUM_RATIONAL)

# PORT: pl-data.h isFloat
"Whether `t` is a float (pl-data.h `isFloat`)."
isFloat(t)::Bool = number_kind(t) === NUM_FLOAT

# PORT: pl-data.h isString
"Whether `t` is a string (pl-data.h `isString`)."
isString(t)::Bool = number_kind(t) === NUM_STRING

# PORT: pl-data.h isTerm
"Whether `t` is a compound term (pl-data.h `isTerm`)."
isTerm(t)::Bool = kind(t) === EXPR

# PORT: pl-data.h isInteger
"Whether `t` is an integer of any size (pl-data.h `isInteger`, `O_BIGNUM`: not a rational)."
isInteger(t)::Bool = number_kind(t) === NUM_INTEGER

# PORT: pl-data.h isNumber
"Whether `t` is a number (pl-data.h `isNumber`): a rational or a float."
isNumber(t)::Bool = isRational(t) || isFloat(t)

# PORT: pl-data.h isAtomic
"Whether `t` is atomic (pl-data.h `isAtomic`): neither a variable nor a compound."
isAtomic(t)::Bool = !canBind(t) && !isTerm(t)

# ── arithmetic (pl-incl.h), V6c ──────────────────────────────────────────────────────────────────
# PORT: pl-incl.h numtype
"The number types (pl-incl.h `numtype`), a TOTAL order: promotion goes up it."
@enum numtype::UInt8 begin
    V_INTEGER                       # integer (64-bit) value
    V_MPZ                           # mpz_t
    V_MPQ                           # mpq_t
    V_FLOAT                         # Floating point number (double)
end

# PORT: pl-incl.h number
# DIVERGES: one field per member of upstream's union — a Julia `Union` field would box the
# integer — so a member not in use keeps a value nobody reads. Pooled in the local data
# (src/pl-arith.jl), where upstream's are C locals.
"A number being computed with (pl-incl.h `number`): its type and its value."
mutable struct number
    type::numtype                   # type of number
    i::Int64                        # value as integer
    f::Float64                      # value as a floating point number
    mpz::BigInt                     # GMP integer
    mpq::Rational{BigInt}           # GMP rational
end
number() = number(V_INTEGER, 0, 0.0, BigInt(0), Rational{BigInt}(0))
