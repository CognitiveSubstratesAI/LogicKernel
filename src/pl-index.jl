# UPSTREAM: swipl-devel src/pl-index.c @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2025, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# JUST-IN-TIME CLAUSE INDEXING — SWI-Prolog's pl-index.c, transliterated function by function under
# upstream's names (`!` appended where a function mutates an argument), in upstream's order, with
# upstream's control flow, constants and `float` arithmetic (Float32 here, so every speedup and
# every decision is the one SWI computes). Upstream's quirks are kept and marked "verbatim".
#
# THE CONTRACT: indexing never changes answers. An index only selects which clauses are TRIED, in
# clause order; the caller unifies each one. `firstClause!` returns the first candidate and leaves
# in the `clause_choice` where `nextClause!` resumes.
#
# PORTED: lookup (`firstClause!`, `first_clause_guarded!`, `nextClause!`, the bucket, list and
# primary-index scans), index creation (`createIndex!`, `bestHash!`, `find_multi_argument_hash!`,
# `hashDefinition!`, `fill_clause_index!`), the assessment, the candidate indexes of static
# predicates (`set_candidate_indexes!`), the primary index (`update_primary_index!`), adding clauses
# to indexes (`addClauseToIndexes!`), deep indexes (list indexes and their sub-indexes), the
# index array (`insertIndex!`, `replaceIndex!`, …) and the `indexed` predicate property
# (`unify_index_pattern`).
#
# Also ported: what retract and clause garbage collection need — deleteActiveClauseFromIndexes and
# what it calls, cleanClauseIndexes and what it calls, shrunkpow2.
#
# NOT PORTED: deleteClauseList, deleteClauseBucket and delClauseFromIndex (nothing calls
# delClauseFromIndex upstream), deleteIndexes and deleteIndexesDefinition (abolish, halt — not
# ported), the memory reports sizeofClauseIndex/sizeofClauseIndexes, the debug checks
# checkClauseIndexSizes/checkClauseIndexes/listIndexGenerations, and the `$candidate_indexes` and
# `$set_candidate_indexes` predicates. Threads (index locks, waiting for another thread's index) do
# not exist in the kernel.
#
# REPRESENTATION (each a DIVERGES at the function it touches):
#   * `argv` — SWI passes a call's arguments as a `Word` vector; here it is a VIEW of them
#     (`argv_frame`: the frame's argument slots; `argv_term`: a compound's arguments, its children
#     2..), read DEREFERENCED as upstream's readers follow references (`argv_at`). A deep index
#     descends into an argument compound by switching to its `argv_term`.
#   * A clause's keys are read from its head CODE (src/pl-comp.jl), exactly as upstream reads
#     them, except that `skipArgs`'s H_VOID_N defect is fixed (LogicKernel#1).
#   * Keys are words in SWI's layout (`indexOfWord`).

# ── PARAMETERS ──────────────────────────────────────────────────────────────────────────────────
# PORT: pl-index.c MIN_SPEEDUP
# DIVERGES: SWI keeps the five parameters in GD->clause_index, settable through the ci_* Prolog
# flags; here they are constants holding the values initClauseIndexing sets.
"Do not create an index if the speedup is less (pl-index.c)."
const MIN_SPEEDUP = 1.5f0
# PORT: pl-index.c MAX_VAR_FRAC
"Do not create an index if the fraction of clauses with a variable in the position exceeds this."
const MAX_VAR_FRAC = 0.1f0
# PORT: pl-index.c MIN_SPEEDUP_RATIO
"Need at least this ratio of #clauses/speedup for creating an index (pl-index.c)."
const MIN_SPEEDUP_RATIO = 3.0f0
# PORT: pl-index.c MAX_LOOKAHEAD
"Most clauses looked ahead for an alternative on indexed clauses (pl-index.c)."
const MAX_LOOKAHEAD = 100
# PORT: pl-index.c MIN_CLAUSES_FOR_INDEX
"Create an index if there are more than this number of clauses (pl-index.c)."
const MIN_CLAUSES_FOR_INDEX = 10

# ── TYPES ───────────────────────────────────────────────────────────────────────────────────────
# PORT: pl-index.c index_context
# DIVERGES: `active` has no upstream field. One context is SHARED per local data (see
# `_index_context!`), which is safe only while firstClause/nextClause are never re-entered mid-call;
# `active` is set on entry, cleared on exit and asserted clear on entry, so a violation — the VM,
# nested queries, deeper indexing may one day cause one — fails loudly, never corrupting a search.
"The state of one clause search (pl-index.c `index_context`)."
mutable struct index_context{T}
    generation::gen_t                               # Current generation
    predicate::Definition{T}                        # Current predicate
    chp::Union{Nothing, ClauseChoice{T}}            # Clause choice point
    depth::Int                                      # current depth (0..)
    position::NTuple{MAXINDEXDEPTH + 1, iarg_t}     # Keep track of argument position
    active::Bool                                    # a search is using it (re-entrance guard)
end

"A position path holding only `END_INDEX_POS` — upstream's `.position[0] = END_INDEX_POS`."
const _TOP_POSITION = (END_INDEX_POS, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)

# PORT: pl-index.c DEAD_INDEX
"A deleted slot in a clause-index array (pl-index.c `DEAD_INDEX`)."
const DEAD_INDEX = nothing
# PORT: pl-index.c ISDEADCI
"True for a deleted slot of a clause-index array (pl-index.c)."
ISDEADCI(ci) = ci === DEAD_INDEX     # no return annotation: inference narrows `ci` through it

# PORT: pl-index.c hash_hints
"What `bestHash!` decided an index should be (pl-index.c `hash_hints`)."
mutable struct hash_hints
    speedup::Float32                        # Expected speedup
    list::Bool                              # Use a list per key
    ln_buckets::UInt8                       # Lg2 of #buckets to use — a 5-bit field upstream
    args::NTuple{MAX_MULTI_INDEX, iarg_t}   # Hash these arguments
end
hash_hints() = hash_hints(0.0f0, false, 0x00, (0x00, 0x00, 0x00, 0x00))

# PORT: pl-index.c STATIC_RELOADING
# DIVERGES: upstream tests LD->reload.generation (a source file being reloaded). There is no reload
# yet, so it is never true.
"True while a static predicate is being reloaded (pl-index.c) — never, until reload exists."
STATIC_RELOADING(def::definition)::Bool = false

# PORT: pl-index.c cref_matches
"Same as `!cref->d.key || cref->d.key == k` (pl-index.c)."
cref_matches(cref::clause_ref, k::word)::Bool = (cref.key == 0) | (cref.key == k)

# PORT: pl-index.c is_clean_predicate
"True if we do not need to check the generation (pl-index.c)."
is_clean_predicate(def::definition)::Bool =
    (def.flags & (P_DYNAMIC | P_DIRTYREG | P_RELOADING)) == 0

# PORT: pl-index.c hashIndex
"Map a key to a bucket of `buckets` (a power of two) by Fibonacci hashing (pl-index.c)."
function hashIndex(key::word, buckets::UInt32)::UInt32
    key_bits = 64
    fib64 = 0x9E3779B97F4A7C15
    shift = key_bits - MSB(buckets)
    key ⊻= (key >> shift)
    return ((fib64 * key) >> shift) % UInt32
end

"""
    argv_frame(ld, base)
    argv_term(ld, t)

The arguments a clause search keys on — upstream's `Word argv` (pl-index.c) — in its two forms: the
frame's argument slots from position `base` (the VM's `ARGP = argFrameP(FR, 0)`), or the arguments
of the compound `t`, its children 2.. (a deep index's descent, and the callers that hold a goal
term). Built per call; neither allocates.
"""
struct argv_frame{L}
    ld::L
    base::Int
end
struct argv_term{L, T}
    ld::L
    t::T
end

"""
    argv_at(argv, i) -> term

Argument `i` (0-based, as upstream's `argv[i]`) of a call, DEREFERENCED: upstream's readers of
`argv` — `indexOfWord`, `canIndex`, `is_var`, the deep descent's `deRef` — follow references, so a
bound argument keys by its value. (A frame slot almost always holds a variable bound to the
argument, so without this no argument would narrow the search.)
"""
argv_at(v::argv_frame, i::Int) = deRef(v.ld, v.ld.slots[v.base + i + 1])
argv_at(v::argv_term, i::Int) = deRef(v.ld, child(v.t, i + 2))

# PORT: pl-index.c canIndex
# DIVERGES: upstream: any non-variable. Upstream also guarantees that `indexOfWord` is non-zero for
# every non-variable; here a grounded value without a `gnd_key`, and a compound whose head is not
# a symbol, are non-variables whose key is 0. They count as NOT indexable, so the guarantee every
# caller relies on (`assert(chp->key)` after `createIndex`) holds.
"True when `t` can select clauses through an index (pl-index.c)."
canIndex(t)::Bool = indexOfWord(t) != 0

"The functor word of a compound named by `name` (see `_functor_name`) with `arity` arguments."
_functor_word(name::UInt64, arity::Int)::word =
    MK_FUNCTOR(UInt64(hash(UInt64(arity), name)), UInt64(arity) & F_ARITY_MASK)

# DIVERGES: upstream names a functor by its atom HANDLE, so `[](a)` and `'[]'(a)` are two functors
# (`[]` is a reserved symbol, `'[]'` a text atom — swipl 10.1.16: `[](a) \== '[]'(a)`). `sym_hash`
# is a TEXT hash, so `[]` takes its own name, `ATOM_nil`, as it does as an atom key.
"The name a functor word takes for the symbol head `h`: `ATOM_nil` for `[]`, else its `sym_hash`."
_functor_name(h)::UInt64 = is_nil(h) ? UInt64(ATOM_nil) : sym_hash(h)

# PORT: pl-index.c indexOfWord
# DIVERGES: reads the term interface rather than a tagged cell, and there are no reference cells to
# follow. VAR → 0, as upstream. SYM → its atom word (`MK_ATOM` of its `sym_hash`, the same in every
# process — SWI's atom numbers are fixed for a given program too), and SWI-7's `[]` → `ATOM_nil`, as
# `argKey` keys `H_NIL`: `sym_hash` is a TEXT hash, so without it `[]` and the atom `'[]'` would
# share a key that upstream's two atom handles never share. GND → its
# `gnd_key` through `clean_index_key` — the role murmur_key plays upstream for strings and floats,
# a key that follows the term type's `gnd_equal` (src/term_interface.jl) — and 0, a wildcard, when
# there is no key. A list cell (`is_pair`) → `FUNCTOR_dot2`, as `argKey` keys `H_LIST*`. EXPR with
# a symbol head → a functor word (`MK_FUNCTOR`) of the name (`_functor_name`) and arity. EXPR with
# any other head — the functor `$expr/n` (Q2, src/pl-ressymbol.jl) → 0, a wildcard: it unifies child
# by child with compounds of other functors.
"""
    indexOfWord(t) -> word

The index key of term `t`: 0 when `t` cannot select clauses, a non-zero word otherwise. A functor
key satisfies `isFunctor`; no other key does.
"""
function indexOfWord(t)::word
    k = kind(t)
    if k === VAR
        return word(0)
    elseif k === SYM
        is_nil(t) && return ATOM_nil                    # `[]`: as `argKey` keys `H_NIL`
        return MK_ATOM(sym_hash(t))
    elseif k === GND
        g = gnd_key(t)
        g === nothing && return word(0)
        return clean_index_key(g)
    end
    nchildren(t) >= 1 || return word(0)                 # `()`: `$expr/0`, a wildcard
    is_pair(t) && return FUNCTOR_dot2                   # `[H|T]`: as `argKey` keys `H_LIST*`
    h = child(t, 1)
    kind(h) === SYM || return word(0)                   # `$expr/n`, a wildcard
    return _functor_word(_functor_name(h), nchildren(t) - 1)
end

# PORT: pl-index.c next_clause_unindexed
"The next clause from `ctx.chp.cref`, without keys (pl-index.c)."
function next_clause_unindexed!(
    ctx::index_context{T}
)::Union{Nothing, ClauseRef{T}} where {T}
    chp = ctx.chp::ClauseChoice{T}
    if is_clean_predicate(ctx.predicate)                                # O_INDEX_STATIC
        cref = chp.cref
        if cref !== nothing
            chp.key = 0
            chp.cref = cref.next
        end
        return cref
    else
        cref = chp.cref
        while cref !== nothing
            if visibleClauseCNT(cref.clause::Clause{T}, ctx.generation)
                chp.key = 0
                setClauseChoice!(cref.next, ctx)
                return cref
            end
            cref = cref.next
        end
        return nothing
    end
end

# PORT: pl-index.c next_clause_primary_index
"""
The next clause from `ctx.chp.cref` whose key matches `ctx.chp.key`, looking up to
`MAX_LOOKAHEAD` clauses ahead for the one after it (pl-index.c).
"""
function next_clause_primary_index!(
    ctx::index_context{T}
)::Union{Nothing, ClauseRef{T}} where {T}
    chp = ctx.chp::ClauseChoice{T}
    key = chp.key
    if is_clean_predicate(ctx.predicate)                                # O_INDEX_STATIC
        cref = chp.cref
        while cref !== nothing
            if cref_matches(cref, key)
                result = cref
                maxsearch = MAX_LOOKAHEAD
                cref = cref.next
                while cref !== nothing
                    if cref_matches(cref, key) || (maxsearch -= 1) == 0
                        chp.cref = cref
                        return result
                    end
                    cref = cref.next
                end
                chp.cref = nothing
                return result
            end
            cref = cref.next
        end
    else
        cref = chp.cref
        while cref !== nothing
            if cref_matches(cref, key) &&
                visibleClauseCNT(cref.clause::Clause{T}, ctx.generation)
                result = cref
                maxsearch = MAX_LOOKAHEAD
                cref = cref.next
                while cref !== nothing
                    if cref_matches(cref, key)
                        if visibleClauseCNT(cref.clause::Clause{T}, ctx.generation)
                            chp.cref = cref
                            return result
                        end
                    end
                    if (maxsearch -= 1) == 0
                        setClauseChoice!(cref, ctx)
                        return result
                    end
                    cref = cref.next
                end
                chp.cref = nothing
                return result
            end
            cref = cref.next
        end
    end
    return nothing
end

# PORT: pl-index.c nextClauseFromList
# DIVERGES: descends into the call's argument compound through its `argv_term` (its children 2..
# are the arguments) rather than into a `Functor` cell.
"""
The next clause from a list index: the clause list of the matching key — descending into a deeper
index when the key is a functor — or, when no list has the key, the list of variable clauses
(pl-index.c).
"""
function nextClauseFromList!(
    ci::ClauseIndex{T}, argv::A, ctx::index_context{T}
)::Union{Nothing, ClauseRef{T}} where {T, A}
    chp = ctx.chp::ClauseChoice{T}
    key = chp.key
    cref = chp.cref
    while cref !== nothing
        if cref.key == key
            cl = cref.clauses::ClauseList{T}
            if isFunctor(cref.key) && ctx.depth < MAXINDEXDEPTH
                an = Int(ci.args[1]) - 1
                at = argv_at(argv, an)
                argc = nchildren(at) - 1
                ctx.position = Base.setindex(ctx.position, an % iarg_t, ctx.depth + 1)
                ctx.depth += 1
                ctx.position = Base.setindex(ctx.position, END_INDEX_POS, ctx.depth + 1)
                return first_clause_guarded!(argv_term(argv.ld, at), argc, cl, ctx)
            end
            chp.key = 0                         # See (*)
            chp.cref = cl.first_clause
            return next_clause_unindexed!(ctx)
        end
        cref = cref.next
    end
    if key != 0
        chp.key = 0
        cref = chp.cref
        while cref !== nothing
            if cref.key == 0
                cl = cref.clauses::ClauseList{T}
                chp.cref = cl.first_clause
                return next_clause_unindexed!(ctx)
            end
            cref = cref.next
        end
    end
    return nothing
end

# PORT: pl-index.c nextClauseFromBucket
"The next clause from a bucket: a list index's lists, or a clause chain (pl-index.c)."
function nextClauseFromBucket!(
    ci::ClauseIndex{T}, argv::A, ctx::index_context{T}
)::Union{Nothing, ClauseRef{T}} where {T, A}
    if ci.is_list
        return nextClauseFromList!(ci, argv, ctx)
    end
    return next_clause_primary_index!(ctx)
end

# PORT: pl-index.c setClauseChoice
"Point the choice at the first clause from `cref` visible in the search's generation (pl-index.c)."
function setClauseChoice!(
    cref::Union{Nothing, ClauseRef{T}}, ctx::index_context{T}
)::Nothing where {T}
    if !is_clean_predicate(ctx.predicate)                               # O_INDEX_STATIC
        while cref !== nothing && !visibleClauseCNT(cref.clause::Clause{T}, ctx.generation)
            cref = cref.next
        end
    end
    (ctx.chp::ClauseChoice{T}).cref = cref
    return nothing
end

# PORT: pl-index.c join_multi_arg_keys
"One key from the keys of a multi-argument index's arguments (pl-index.c)."
function join_multi_arg_keys(key::NTuple{MAX_MULTI_INDEX, word}, len::Int)::word
    k = word(MurmurHashAligned2(key, 8 * len, MURMUR_SEED))
    return clean_index_key(k)
end

# PORT: pl-index.c indexKeyFromArgv
"The key of the call `argv` for index `ci`; 0 when an indexed argument is unbound (pl-index.c)."
function indexKeyFromArgv(ci::ClauseIndex{T}, argv::A)::word where {T, A}
    if ci.args[2] == 0
        return indexOfWord(argv_at(argv, Int(ci.args[1]) - 1))
    else
        key = (word(0), word(0), word(0), word(0))
        harg = 0
        while harg < MAX_MULTI_INDEX && ci.args[harg + 1] != 0          # bounded: see below
            k = indexOfWord(argv_at(argv, Int(ci.args[harg + 1]) - 1))
            k == 0 && return word(0)
            key = Base.setindex(key, k, harg + 1)
            harg += 1
        end
        return join_multi_arg_keys(key, harg)
    end
end
# (Upstream's loops over `args` stop at the first 0 without a bound; all MAX_MULTI_INDEX slots in
# use would read past the array. The bound changes nothing for the at most two arguments in use.)

# PORT: pl-index.c is_var
# DIVERGES: a term-interface variable; there are no reference chains to follow.
"True when the argument `t` is an unbound variable (pl-index.c)."
is_var(t)::Bool = kind(t) === VAR

# PORT: pl-index.c is_satifies_index
"Quick test whether a not-yet-realised index can be used for the call `argv` (pl-index.c)."
function is_satifies_index(ci::ClauseIndex{T}, argv::A)::Bool where {T, A}
    a0 = ci.args[1]
    if a0 == 0 || is_var(argv_at(argv, Int(a0) - 1))
        return false                    # DEAD_INDEX and var first arg
    end
    i = 2
    while i <= MAX_MULTI_INDEX && (a0 = ci.args[i]) != 0
        if is_var(argv_at(argv, Int(a0) - 1))
            return false
        end
        i += 1
    end
    return true
end

# PORT: pl-index.c consider_better_index
"Given an index with `speedup` for `nclauses`, should we look for a better one? (pl-index.c)"
consider_better_index(speedup::Float32, nclauses::Integer)::Bool =
    nclauses > MIN_CLAUSES_FOR_INDEX && Float32(nclauses) / speedup > MIN_SPEEDUP_RATIO

# PORT: pl-index.c existing_hash
# DIVERGES: returns the key with the index instead of writing it through `keyp`.
"The first index the call `argv` has a key for, and that key (pl-index.c)."
function existing_hash(
    cip::Vector{C}, argv::A
)::Tuple{C, word} where {C <: Union{Nothing, ClauseIndex}, A}
    for ci in cip
        ISDEADCI(ci) && continue        # upstream reads the zeroed DEAD_INDEX and skips it
        if ci.entries !== nothing || is_satifies_index(ci, argv)
            k = indexKeyFromArgv(ci, argv)
            if k != 0
                return (ci, k)
            end
        end
    end
    return (nothing, word(0))
end

"The type of `CI_RETRY`."
struct ci_retry_t end
# PORT: pl-index.c CI_RETRY
"`createIndex!`'s result when the index was invalidated while being built (pl-index.c)."
const CI_RETRY = ci_retry_t()

# PORT: pl-index.c createIndex
"""
Add a new index to the clause list if it provides a speedup of at least `MIN_SPEEDUP` — better
than `better_than` when given. Returns the index, `nothing` when no better index is possible, or
`CI_RETRY` (pl-index.c).
"""
function createIndex!(
    argv::A, argc::Int, clist::ClauseList{T}, better_than::Union{Nothing, ClauseIndex{T}},
    ctx::index_context{T}
)::Union{Nothing, ClauseIndex{T}, ci_retry_t} where {T, A}
    hints = hash_hints()
    if bestHash!(argv, argc, clist, better_than, hints, ctx)
        ci = hashDefinition!(clist, hints, ctx)
        if ci !== nothing
            while ci.incomplete
                wait_for_index!(ci, clist, ctx)
            end
            if ci.invalid
                return CI_RETRY
            end
            return ci
        end
        return CI_RETRY
    end
    return nothing
end

# PORT: pl-index.c first_clause_guarded
"""
Find the first clause of `clist` that may match the call `argv` (with `argc` arguments) and leave
in `ctx.chp` where the search resumes (pl-index.c).
"""
function first_clause_guarded!(
    argv::A, argc::Int, clist::ClauseList{T}, ctx::index_context{T}
)::Union{Nothing, ClauseRef{T}} where {T, A}
    chp = ctx.chp::ClauseChoice{T}
    cref::Union{Nothing, ClauseRef{T}} = nothing
    # If `clist->unindexed`, no primary index is possible.
    if clist.unindexed || argc == 0
        chp.cref = clist.first_clause
        return next_clause_unindexed!(ctx)
    end
    @label retry
    cref = nothing
    if clist.number_of_clauses == 0
        return nothing
    end
    pindex = Int(clist.primary_index)
    pkey = indexOfWord(argv_at(argv, pindex))
    # Fast path (#1386): at the outermost call, if the primary-index argument is bound and the
    # predicate is small, try the primary index before probing candidate hash indexes.
    if pkey != 0 && ctx.depth == 0 &&
        (
            clist.number_of_clauses <= MIN_CLAUSES_FOR_INDEX ||
            STATIC_RELOADING(ctx.predicate)
        )
        chp.key = pkey
        chp.cref = clist.first_clause
        cref = next_clause_primary_index!(ctx)
        if cref === nothing ||
            !(
            chp.cref !== nothing && (chp.cref::ClauseRef{T}).key == pkey && cref.key == pkey
        )
            return cref
        end
        # else duplicate primary key: fall through to try hash
    end
    # Deal with possible hashes
    cip = clist.clause_indexes
    if cip !== nothing
        best_index, k = existing_hash(cip, argv)
        if best_index !== nothing
            chp.key = k
            if !best_index.good
                if !clist.fixed_indexes && !STATIC_RELOADING(ctx.predicate) &&
                    consider_better_index(best_index.speedup, clist.number_of_clauses)
                    ci = createIndex!(argv, argc, clist, best_index, ctx)
                    if ci !== nothing
                        if ci === CI_RETRY
                            @goto retry
                        end
                        ci = ci::ClauseIndex{T}
                        chp.key = indexKeyFromArgv(ci, argv)
                        @assert chp.key != 0
                        best_index = ci
                    end
                end
                if best_index.incomplete
                    wait_for_index!(best_index, clist, ctx)
                    @goto retry
                end
            end
            hi = hashIndex(chp.key, best_index.buckets)
            bkt = (best_index.entries::Vector{ClauseBucket{T}})[hi + 1]
            if bkt.key != 0 && chp.key != bkt.key
                return nothing
            end
            chp.cref = bkt.head
            return nextClauseFromBucket!(best_index, argv, ctx)
        end
    end
    chp.key = pkey                      # existing_hash may have overwritten it
    if clist.fixed_indexes              # set_candidate_indexes() has been run
        chp.cref = clist.first_clause
        if chp.key != 0
            return next_clause_primary_index!(ctx)
        else
            return next_clause_unindexed!(ctx)
        end
    end
    if (ctx.predicate.flags & (P_DYNAMIC | P_MULTIFILE | P_THREAD_LOCAL | P_FOREIGN)) ==
       0 &&
        ctx.depth == 0
        set_candidate_indexes!(ctx.predicate, clist, 10, true)
        @goto retry
    end
    if !STATIC_RELOADING(ctx.predicate)
        ci = createIndex!(argv, argc, clist, nothing, ctx)
        if ci !== nothing
            if ci === CI_RETRY
                @goto retry
            end
            ci = ci::ClauseIndex{T}
            chp.key = indexKeyFromArgv(ci, argv)
            @assert chp.key != 0
            hi = hashIndex(chp.key, ci.buckets)
            chp.cref = (ci.entries::Vector{ClauseBucket{T}})[hi + 1].head
            return nextClauseFromBucket!(ci, argv, ctx)
        end
    end
    if cref !== nothing                 # from primary-first fast-path fallthrough
        return cref
    end
    chp.cref = clist.first_clause
    if chp.key != 0
        return next_clause_primary_index!(ctx)
    else
        return next_clause_unindexed!(ctx)
    end
end

"""
The search context for one call of `firstClause!`/`nextClause!`: the local data's scratch
`index_ctx`, reset — upstream declares a fresh `index_context` on the C stack. One per local data
is enough: neither function is entered again before it returns (a caller's nested enumeration runs
BETWEEN calls, and resets it in turn), and nothing keeps the context past the call. A context per
call was a heap allocation on every `nextClause!` — every step of every enumeration.
"""
function _index_context!(
    ctx::index_context{T}, generation::gen_t, def::Definition{T}, chp::ClauseChoice{T}
)::index_context{T} where {T}
    @assert !ctx.active "firstClause!/nextClause! re-entered: the shared index_context is in use"
    ctx.active = true
    ctx.generation = generation
    ctx.predicate = def
    ctx.chp = chp
    ctx.depth = 0
    ctx.position = _TOP_POSITION
    return ctx
end

# PORT: pl-index.c firstClause
# DIVERGES: takes the search's generation where upstream takes a frame (`generationFrame(fr)`), and
# the local data `ld` explicitly (its scratch context, see `_index_context!`; untyped only because
# `PL_local_data` is defined after this file, which defines the context it holds); there is no
# definition reference counting (acquire_def/release_def) — that serves clause GC.
"""
    firstClause!(ld, argv, generation, def, chp) -> Union{Nothing, ClauseRef}

The first clause of `def` that may match the call whose arguments `argv` views (`argv_frame` or
`argv_term`), visible in `generation`; `chp` records where `nextClause!` resumes (pl-index.c).
"""
function firstClause!(
    ld, argv::A, generation::gen_t, def::Definition{T}, chp::ClauseChoice{T}
)::Union{Nothing, ClauseRef{T}} where {T, A}
    ctx = _index_context!(ld.index_ctx::index_context{T}, generation, def, chp)
    try
        return first_clause_guarded!(argv, def.arity, def.impl_clauses, ctx)
    finally
        ctx.active = false
    end
end

# PORT: pl-index.c nextClause
# DIVERGES: as `firstClause!` — a generation instead of a frame, `ld` explicit, no definition
# reference counting. Allocation-free (AllocCheck gate): every step of an enumeration takes it.
"""
    nextClause!(ld, chp, argv, generation, def) -> Union{Nothing, ClauseRef}

The next candidate clause after the ones `chp` has produced (pl-index.c).
"""
function nextClause!(
    ld, chp::ClauseChoice{T}, argv::A, generation::gen_t, def::Definition{T}
)::Union{Nothing, ClauseRef{T}} where {T, A}
    ctx = _index_context!(ld.index_ctx::index_context{T}, generation, def, chp)
    try
        if chp.key == 0                 # not indexed
            return next_clause_unindexed!(ctx)
        else
            return next_clause_primary_index!(ctx)
        end
    finally
        ctx.active = false
    end
end

# ── HASH SUPPORT ────────────────────────────────────────────────────────────────────────────────
# PORT: pl-index.c cmp_iarg
"Order of index arguments (pl-index.c)."
cmp_iarg(u1::iarg_t, u2::iarg_t)::Int =
    if u1 < u2
        -1
    elseif u1 > u2
        1
    else
        0
    end

# PORT: pl-index.c canonicalHap
# DIVERGES: returns the canonical tuple instead of sorting an array in place.
"Index arguments in canonical form: zeros after the first zero, the rest ascending (pl-index.c)."
function canonicalHap(hap::NTuple{MAX_MULTI_INDEX, iarg_t})::NTuple{MAX_MULTI_INDEX, iarg_t}
    i = 0
    while i < MAX_MULTI_INDEX
        if hap[i + 1] == 0
            for j in (i + 1):MAX_MULTI_INDEX
                hap = Base.setindex(hap, 0x00, j)
            end
            break
        end
        i += 1
    end
    for a in 2:i                        # qsort(hap, i, sizeof(*hap), cmp_iarg)
        b = a
        while b > 1 && cmp_iarg(hap[b - 1], hap[b]) > 0
            x = hap[b]
            hap = Base.setindex(hap, hap[b - 1], b)
            hap = Base.setindex(hap, x, b - 1)
            b -= 1
        end
    end
    return hap
end

# PORT: pl-index.c copytpos
# DIVERGES: returns the copy (zero after `END_INDEX_POS`, as the memset target upstream) instead of
# writing through a pointer.
"A copy of a position path up to and including `END_INDEX_POS` (pl-index.c)."
function copytpos(
    from::NTuple{MAXINDEXDEPTH + 1, iarg_t}
)::NTuple{MAXINDEXDEPTH + 1, iarg_t}
    to = (0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
    k = 1
    while true
        p = from[k]
        to = Base.setindex(to, p, k)
        p == END_INDEX_POS && break
        k += 1
    end
    return to
end

# PORT: pl-index.c realize_clause_index
"Allocate the buckets of a not yet realised index; true if this call did it (pl-index.c)."
function realize_clause_index!(ci::ClauseIndex{T})::Bool where {T}
    if ci.entries === nothing
        ci.entries = [ClauseBucket{T}() for _ in 1:ci.buckets]
        return true
    end
    return false
end

# PORT: pl-index.c newClauseIndexTable
"A new, incomplete index as `hints` describe it, realised or not (pl-index.c)."
function newClauseIndexTable(
    hints::hash_hints, realised::Bool, ctx::index_context{T}
)::ClauseIndex{T} where {T}
    ci = ClauseIndex{T}(
        UInt32(2) << hints.ln_buckets, UInt32(0), UInt32(0), UInt32(0), UInt32(0),
        hints.list, true, false, false, hints.args, copytpos(ctx.position), hints.speedup,
        nothing
    )
    if realised
        realize_clause_index!(ci)
    end
    return ci
end

# PORT: pl-index.c newClauseListRef
"A list cell for `key` in a list index, holding an empty clause list (pl-index.c)."
newClauseListRef(::Type{T}, key::word) where {T} =
    ClauseRef{T}(nothing, key, nothing, ClauseList{T}())

# PORT: pl-index.c addToClauseList
"Add `clause` with key `key` to the clause list of the list cell `cref` (pl-index.c)."
function addToClauseList!(
    cref::ClauseRef{T}, clause::Clause{T}, key::word, where_::Union{Int, ClauseRef{T}}
)::Nothing where {T}
    def = clause.predicate
    cl = cref.clauses::ClauseList{T}
    cr = newClauseRef(clause, key)
    if cl.first_clause !== nothing
        if where_ === CL_END
            (cl.last_clause::ClauseRef{T}).next = cr
            cl.last_clause = cr
        elseif where_ === CL_START
            cr.next = cl.first_clause
            cl.first_clause = cr
        else
            cl.first_clause, cl.last_clause = insertIntoSparseList!(
                cr, cl.first_clause, cl.last_clause, where_
            )
        end
        cl.number_of_clauses += 1
    else
        cl.first_clause = cl.last_clause = cr
        cl.number_of_clauses = 1
    end
    addClauseToListIndexes!(def, cl, clause, where_)
    return nothing
end

# PORT: pl-index.c addClauseToListIndexes
"Add `clause` to every realised index of `cl`, dropping an index that cannot take it (pl-index.c)."
function addClauseToListIndexes!(
    def::Definition{T}, cl::ClauseList{T}, clause::Clause{T},
    where_::Union{Int, ClauseRef{T}}
)::Nothing where {T}
    cip = cl.clause_indexes
    if cip !== nothing
        for i in eachindex(cip)
            ci = cip[i]
            if ISDEADCI(ci) || ci.entries === nothing
                continue
            end
            while ci.incomplete
                wait_for_index!(ci, cl, nothing)
            end
            if ci.invalid
                continue
            end
            if ci.size >= ci.resize_above || !addClauseToIndex!(ci, clause, where_)
                deleteIndexP!(def, cl, cip, i)
            end
        end
    end
    return nothing
end

# PORT: pl-index.c insertIntoSparseList
# DIVERGES: takes the list's head and tail and returns them updated, where upstream writes through
# `ClauseRef *headp, *tailp`.
"""
Insert `cref` into the sparse (filtered) clause list `head`…`tail` — at its end, its start, or
before the clause reference `where_` of the predicate's clause list (pl-index.c).
"""
function insertIntoSparseList!(
    cref::ClauseRef{T}, head::Union{Nothing, ClauseRef{T}},
    tail::Union{Nothing, ClauseRef{T}},
    where_::Union{Int, ClauseRef{T}}
)::Tuple{ClauseRef{T}, ClauseRef{T}} where {T}
    if head === nothing
        return (cref, cref)
    end
    # Upstream's invariant, made explicit: a list with a head has a tail. A bare `tail::ClauseRef{T}`
    # left JET, which splits the two unions independently, a head-without-tail case it could not rule
    # out — reported as an invalid `typeassert` once the precompile workload gave JET a concrete call
    # path here (2026-10-03).
    tail === nothing &&
        error("insertIntoSparseList!: a sparse clause list has a head but no tail")
    if where_ === CL_END
        tail.next = cref
        return (head, cref)
    elseif where_ === CL_START
        cref.next = head
        return (cref, tail)
    else
        clause = cref.clause::Clause{T}
        pred_cref = clause.predicate.impl_clauses.first_clause
        ci_cref::Union{Nothing, ClauseRef{T}} = head
        ci_prev::Union{Nothing, ClauseRef{T}} = nothing
        while pred_cref !== nothing
            if pred_cref === where_ || ci_prev === tail
                if ci_cref === head
                    cref.next = head
                    return (cref, tail)
                elseif ci_prev === tail
                    tail.next = cref
                    return (head, cref)
                else
                    cref.next = ci_cref
                    (ci_prev::ClauseRef{T}).next = cref
                    return (head, tail)
                end
            end
            if pred_cref.clause === (ci_cref::ClauseRef{T}).clause
                ci_prev = ci_cref
                ci_cref = (ci_cref::ClauseRef{T}).next
            end
            pred_cref = pred_cref.next
        end
        return (head, tail)
    end
end

# PORT: pl-index.c addClauseBucket
"""
Add a clause to a bucket; returns how many indexable entries were added (pl-index.c). In a list
index a key denotes a clause list; a variable clause (key 0) goes into EVERY clause list of the
bucket, and a new clause list starts with the variable clauses already there.
"""
function addClauseBucket!(
    ch::ClauseBucket{T}, cl::Clause{T}, key::word, arg1key::word,
    where_::Union{Int, ClauseRef{T}}, is_list::Bool
)::Int where {T}
    local cr::ClauseRef{T}
    if is_list
        vars::Union{Nothing, ClauseList{T}} = nothing
        if key != 0
            cref = ch.head
            while cref !== nothing
                if cref.key == key
                    addToClauseList!(cref, cl, arg1key, where_)
                    return 0
                elseif cref.key == 0
                    vars = cref.clauses::ClauseList{T}
                end
                cref = cref.next
            end
        else
            cref = ch.head
            while cref !== nothing
                if cref.key == 0
                    vars = cref.clauses::ClauseList{T}
                end
                addToClauseList!(cref, cl, arg1key, where_)
                cref = cref.next
            end
            if vars !== nothing
                return 0
            end
        end
        cr = newClauseListRef(T, key)
        if vars !== nothing                                             # (**)
            crl = cr.clauses::ClauseList{T}
            vref = vars.first_clause
            while vref !== nothing
                vcl = vref.clause::Clause{T}
                addToClauseList!(cr, vcl, arg1key, CL_END)
                if (vcl.flags & CL_ERASED) != 0                         # or do not add?
                    crl.number_of_clauses -= 1
                    crl.erased_clauses += 1
                end
                vref = vref.next
            end
            if crl.erased_clauses != 0
                ch.dirty += 1
            end
        end
        addToClauseList!(cr, cl, arg1key, where_)
    else
        cr = newClauseRef(cl, key)
        if ch.head === nothing
            ch.key = key
        elseif ch.key != key
            ch.key = 0                  # collision
        end
    end
    if is_list
        where_ = CL_START               # doesn't matter where we insert
    end
    ch.head, ch.tail = insertIntoSparseList!(cr, ch.head, ch.tail, where_)
    return key != 0 ? 1 : 0
end

# ── reconsidering indexes (pl-index.c) ──────────────────────────────────────────────────────────
# PORT: pl-index.c clearTriedIndexes
"Forget the per-argument assessments of `def` (pl-index.c)."
function clearTriedIndexes!(def::Definition{T})::Nothing where {T}
    arity = def.arity
    args = def.impl_clauses.args::Vector{arg_info}
    for i in 0:(arity - 1)
        ainfo = args[i + 1]
        ainfo.assessed = false
    end
    def.impl_clauses.jiti_tried = 0
    return nothing
end

# PORT: pl-index.c reconsiderIndexes
"""
Reset the JIT indexing decisions cached on `def` — called when the predicate's supervisor changes,
i.e. its clause shape changed (pl-index.c). The index tables themselves are kept.
"""
function reconsiderIndexes!(def::Definition{T})::Nothing where {T}
    if (def.flags & P_FOREIGN) != 0
        return nothing
    end
    clist = def.impl_clauses
    if clist.args !== nothing
        arity = def.arity
        for i in 0:(arity - 1)
            (clist.args::Vector{arg_info})[i + 1].assessed = false
        end
    end
    clist.jiti_tried = 0
    clist.pindex_verified = false
    clist.fixed_indexes = false
    clist.unindexed = false
    return nothing
end

# PORT: pl-index.c has_pow2_clauses
"True when the number of clauses of `def` is a power of two (pl-index.c)."
function has_pow2_clauses(def::definition)::Bool
    nc = def.impl_clauses.number_of_clauses
    return nc > 0 && (UInt32(1) << MSB(nc)) == nc
end

# PORT: pl-index.c reconsider_index
"For a dynamic predicate at a power-of-two clause count, forget the assessments (pl-index.c)."
function reconsider_index!(def::Definition{T})::Nothing where {T}
    if (def.flags & P_DYNAMIC) != 0
        if has_pow2_clauses(def)
            if (def.flags & P_SHRUNKPOW2) != 0
                def.flags &= ~P_SHRUNKPOW2
            else
                clearTriedIndexes!(def)
            end
        end
    end
    return nothing
end

# PORT: pl-index.c shrunkpow2
"A dynamic predicate at a power-of-two clause count while shrinking: mark it (pl-index.c)."
function shrunkpow2!(def::Definition{T})::Nothing where {T}
    if (def.flags & P_DYNAMIC) != 0
        if (def.flags & P_SHRUNKPOW2) == 0 && has_pow2_clauses(def)
            def.flags |= P_SHRUNKPOW2
        end
    end
    return nothing
end

# ── removing clauses from indexes (pl-index.c) ──────────────────────────────────────────────────
# A retracted clause cannot leave an index at once: an enumeration of an older generation may
# still need it. Retract only counts it as DIRTY (`deleteActiveClauseFromIndexes!`); clause GC
# unlinks it once no generation in use can see it (`cleanClauseIndexes!`).
# NOT PORTED: deleteClauseList and deleteClauseBucket (reached only from delClauseFromIndex, which
# nothing calls upstream), deleteIndexes and deleteIndexesDefinition (abolish, halt), and the
# memory release of unlinked references (freeClauseListRef, lingerClauseRef) — the garbage
# collector's job here; an unlinked reference keeps its `next`, as upstream's lingering one does,
# so an enumeration standing on it continues.

# PORT: pl-index.c gcClauseList
# DIVERGES: no transactions, so no `tr_starts`.
"Unlink the clauses of a list index's clause list that are garbage (pl-index.c)."
function gcClauseList!(
    clist::ClauseList{T}, ddi::dirty_def_info{T}, start::gen_t
)::Nothing where {T}
    cref = clist.first_clause
    prev::Union{Nothing, ClauseRef{T}} = nothing
    left = 0
    while cref !== nothing && clist.erased_clauses != 0
        cl = cref.clause::Clause{T}
        if (cl.flags & CL_ERASED) != 0
            if ddi_is_garbage(ddi, start, cl)
                c = cref
                clist.erased_clauses -= 1
                cref = cref.next
                if prev === nothing
                    clist.first_clause = c.next
                    if c.next === nothing
                        clist.last_clause = nothing
                    end
                else
                    prev.next = c.next
                    if c.next === nothing
                        clist.last_clause = prev
                    end
                end
                continue                            # lingerClauseRef(c)
            else
                left += 1
            end
        end
        prev = cref
        cref = cref.next
    end
    clist.erased_clauses = left                     # see (*)
    return nothing
end

# PORT: pl-index.c gcClauseBucket
# DIVERGES: no transactions, so no `tr_starts`.
"""
Unlink the garbage clauses (or emptied clause lists) of a bucket; the number of indexable entries
removed (pl-index.c).
"""
function gcClauseBucket!(
    def::Definition{T}, ch::ClauseBucket{T}, dirty::UInt32, is_list::Bool,
    ddi::dirty_def_info{T}, start::gen_t
)::Int where {T}
    cref = ch.head
    prev::Union{Nothing, ClauseRef{T}} = nothing
    deleted = 0
    while cref !== nothing && dirty != 0
        delete = false
        if is_list
            cl = cref.clauses::ClauseList{T}
            if cl.erased_clauses != 0
                gcClauseList!(cl, ddi, start)
                if cl.erased_clauses == 0
                    dirty -= 0x00000001
                end
                if cl.first_clause === nothing
                    delete = true                   # goto delete
                end
            end
        else
            cl = cref.clause::Clause{T}
            if (cl.flags & CL_ERASED) != 0 && ddi_is_garbage(ddi, start, cl)
                dirty -= 0x00000001
                delete = true
            end
        end
        if delete
            c = cref
            if cref.key != 0
                deleted += 1                        # only reduce size by indexed
            end
            cref = cref.next
            if prev === nothing
                ch.head = c.next
                if c.next === nothing
                    ch.tail = nothing
                end
            else
                prev.next = c.next
                if c.next === nothing
                    ch.tail = prev
                end
            end
            continue                                # lingerClauseListRef / lingerClauseRef
        end
        prev = cref
        cref = cref.next
    end
    ch.dirty = dirty
    return deleted
end

# PORT: pl-index.c cleanClauseIndex
# DIVERGES: no transactions, so no `tr_starts`.
"Drop an index the predicate has shrunk below, or clean its dirty buckets (pl-index.c)."
function cleanClauseIndex!(
    def::Definition{T}, cl::ClauseList{T}, ci::ClauseIndex{T}, ddi::dirty_def_info{T},
    start::gen_t
)::Nothing where {T}
    if cl.number_of_clauses < ci.resize_below
        deleteIndex!(def, cl, ci)
    else
        if ci.dirty != 0
            entries = ci.entries::Vector{ClauseBucket{T}}
            for ch in entries
                if ch.dirty != 0
                    ci.size -= gcClauseBucket!(def, ch, ch.dirty, ci.is_list, ddi, start)
                    if ch.dirty == 0 && (ci.dirty -= 0x00000001) == 0
                        break
                    end
                end
            end
        end
    end
    return nothing
end

# PORT: pl-index.c cleanClauseIndexes
# DIVERGES: no transactions, so no `tr_starts`.
"Clean every index of `cl` after clause GC removed clauses from it (pl-index.c)."
function cleanClauseIndexes!(
    def::Definition{T}, cl::ClauseList{T}, ddi::dirty_def_info{T}, start::gen_t
)::Nothing where {T}
    cip = cl.clause_indexes
    if cip !== nothing
        for ci in cip
            if ISDEADCI(ci)
                continue
            end
            cleanClauseIndex!(def, cl, ci, ddi, start)
        end
    end
    return nothing
end

# PORT: pl-index.c deleteActiveClauseFromBucket
"""
Count a retracted clause in the clause lists of a list-index bucket — every list for a clause
without a key, the list of its key otherwise (pl-index.c).
"""
function deleteActiveClauseFromBucket!(cb::ClauseBucket{T}, key::word)::Nothing where {T}
    if key == 0
        cref = cb.head
        while cref !== nothing
            cl = cref.clauses::ClauseList{T}
            if (cl.erased_clauses += 1) - 1 == 0       # cl->erased_clauses++ == 0
                cb.dirty += 0x00000001
            end
            cl.number_of_clauses -= 0x00000001
            cref = cref.next
        end
    else
        cref = cb.head
        while cref !== nothing
            if cref.key == key
                cl = cref.clauses::ClauseList{T}
                if (cl.erased_clauses += 1) - 1 == 0
                    cb.dirty += 0x00000001
                end
                cl.number_of_clauses -= 0x00000001
                return nothing
            end
            cref = cref.next
        end
        @assert false "deleteActiveClauseFromBucket!: key not in bucket"
    end
    return nothing
end

# PORT: pl-index.c deleteActiveClauseFromIndex
"Mark the buckets that hold a retracted clause dirty, for clause GC (pl-index.c)."
function deleteActiveClauseFromIndex!(ci::ClauseIndex{T}, cl::Clause{T})::Nothing where {T}
    key, _ = indexKeyFromClause(ci, cl)
    entries = ci.entries::Vector{ClauseBucket{T}}
    if key == 0                                     # not indexed
        for cb in entries
            if cb.dirty == 0
                ci.dirty += 0x00000001
            end
            if ci.is_list
                deleteActiveClauseFromBucket!(cb, key)
            else
                cb.dirty += 0x00000001
            end
        end
        @assert ci.dirty == ci.buckets
    else
        hi = hashIndex(key, ci.buckets)
        cb = entries[hi + 1]
        if cb.dirty == 0
            ci.dirty += 0x00000001
        end
        if ci.is_list
            deleteActiveClauseFromBucket!(cb, key)
        else
            cb.dirty += 0x00000001
        end
        @assert cb.dirty > 0
    end
    return nothing
end

# PORT: pl-index.c deleteActiveClauseFromIndexes
"""
A clause of `def` was retracted: drop an index the predicate has shrunk below (any index of a
static predicate), or mark the clause dirty in it (pl-index.c).
"""
function deleteActiveClauseFromIndexes!(
    def::Definition{T}, cl::Clause{T}
)::Nothing where {T}
    shrunkpow2!(def)
    cip = def.impl_clauses.clause_indexes
    if cip !== nothing
        for i in eachindex(cip)
            ci = cip[i]
            if ISDEADCI(ci) || ci.entries === nothing
                continue
            end
            while ci.incomplete
                wait_for_index!(ci, def.impl_clauses, nothing)
            end
            if ci.invalid
                continue
            end
            if (def.flags & P_DYNAMIC) != 0
                if def.impl_clauses.number_of_clauses < ci.resize_below
                    deleteIndexP!(def, def.impl_clauses, cip, i)
                else
                    deleteActiveClauseFromIndex!(ci, cl)
                end
            else
                deleteIndexP!(def, def.impl_clauses, cip, i)
            end
        end
    end
    return nothing
end

# ── adding clauses to indexes (pl-index.c) ──────────────────────────────────────────────────────
# PORT: pl-index.c indexKeyFromClause
# DIVERGES: returns the key with the code position of the indexed argument, where upstream writes
# the position through `end` (left unset in the multi-argument case — it is never read there).
"The key of clause `cl` for index `ci`, and the position of the indexed argument (pl-index.c)."
function indexKeyFromClause(ci::ClauseIndex{T}, cl::Clause{T})::Tuple{word, Code} where {T}
    h_void = 0
    PC, h_void = skipToTerm(cl, ci.position, h_void)
    if ci.args[2] == 0
        arg = Int(ci.args[1]) - 1
        if arg > 0
            PC, h_void = skipArgs(PC, arg, h_void)
        end
        return (argKey(PC, 0), PC)
    else
        key = (word(0), word(0), word(0), word(0))
        pcarg = 1
        harg = 0
        while harg < MAX_MULTI_INDEX && ci.args[harg + 1] != 0
            if Int(ci.args[harg + 1]) > pcarg
                PC, h_void = skipArgs(PC, Int(ci.args[harg + 1]) - pcarg, h_void)
            end
            pcarg = Int(ci.args[harg + 1])
            k = argKey(PC, 0)
            if k == 0
                return (word(0), PC)
            end
            key = Base.setindex(key, k, harg + 1)
            harg += 1
        end
        return (join_multi_arg_keys(key, harg), PC)
    end
end

# PORT: pl-index.c addClauseToIndex
"""
Add clause `cl` to index `ci`: a non-indexable clause (key 0) goes into every bucket. False when a
list index cannot take the clause (pl-index.c).
"""
function addClauseToIndex!(
    ci::ClauseIndex{T}, cl::Clause{T}, where_::Union{Int, ClauseRef{T}}
)::Bool where {T}
    ch = ci.entries
    arg1key = word(0)
    if ch === nothing
        return true
    end
    key, pc = indexKeyFromClause(ci, cl)
    if ci.is_list                       # find first argument key for term
        if key == 0
            return false
        end
        c = decode(pc)
        if c == H_FUNCTOR || c == H_LIST || c == H_RFUNCTOR || c == H_RLIST
            pc = stepPC(pc)
            arg1key = argKey(pc, 0)
        end
    end
    if key == 0                         # a non-indexable field
        for n in 1:ci.buckets
            addClauseBucket!(ch[n], cl, key, arg1key, where_, ci.is_list)
        end
    else
        hi = hashIndex(key, ci.buckets)
        ci.size += addClauseBucket!(ch[hi + 1], cl, key, arg1key, where_, ci.is_list)
    end
    return true
end

# PORT: pl-index.c addClauseToIndexes
"Add a newly asserted clause to the predicate's indexes — called only by `assertDefinition!`."
function addClauseToIndexes!(
    def::Definition{T}, clause::Clause{T}, where_::Union{Int, ClauseRef{T}}
)::Bool where {T}
    addClauseToListIndexes!(def, def.impl_clauses, clause, where_)
    reconsider_index!(def)
    return true
end

# PORT: pl-index.c wait_for_index
# DIVERGES: there are no threads, so there is no other thread's index to wait for; what remains
# realises and fills an index nobody has started.
"Realise and fill index `ci` if no one has yet (pl-index.c)."
function wait_for_index!(
    ci::ClauseIndex{T}, clist::ClauseList{T}, ctx::Union{Nothing, index_context{T}}
)::Nothing where {T}
    if ci.entries === nothing && ctx !== nothing && realize_clause_index!(ci)
        if fill_clause_index!(ci, clist, ctx) === nothing
            ci.invalid = true
            return nothing
        end
    end
    return nothing
end

# PORT: pl-index.c completed_index
"Mark index `ci` complete (pl-index.c)."
function completed_index!(ci::clause_index)::Nothing
    ci.incomplete = false
    return nothing
end

# PORT: pl-index.c fill_clause_index
"Add every live clause of `clist` to the new index `ci` (pl-index.c)."
function fill_clause_index!(
    ci::ClauseIndex{T}, clist::ClauseList{T}, ctx::index_context{T}
)::Union{Nothing, ClauseIndex{T}} where {T}
    cref = clist.first_clause
    while cref !== nothing
        cl = cref.clause::Clause{T}
        if (cl.flags & CL_ERASED) == 0
            if !addClauseToIndex!(ci, cl, CL_END)
                ci.invalid = true
                completed_index!(ci)
                deleteIndex!(ctx.predicate, clist, ci)
                return nothing
            end
        end
        cref = cref.next
    end
    ci.resize_above = ci.size * 2
    ci.resize_below = ci.size ÷ 4
    completed_index!(ci)
    if !consider_better_index(ci.speedup, clist.number_of_clauses)
        ci.good = true                  # `good` means complete and sufficient
    end
    return ci
end

# PORT: pl-index.c hashDefinition
"The index `hints` describe: an existing one with the same arguments, or a new filled one."
function hashDefinition!(
    clist::ClauseList{T}, hints::hash_hints, ctx::index_context{T}
)::Union{Nothing, ClauseIndex{T}} where {T}
    hints.args = canonicalHap(hints.args)
    cip = clist.clause_indexes
    if cip !== nothing
        for cio in cip
            if ISDEADCI(cio)
                continue
            end
            if cio.args == hints.args
                return cio              # already created
            end
        end
    end
    ci = newClauseIndexTable(hints, true, ctx)
    insertIndex!(ctx.predicate, clist, ci)
    return fill_clause_index!(ci, clist, ctx)
end

# PORT: pl-index.c copyIndex
# DIVERGES: `org` is never NULL at upstream's two call sites, and is typed so here.
"A copy of an index array without its dead slots, with `add` inserted by speedup (pl-index.c)."
function copyIndex(org::Vector{S}, add)::Union{Nothing, Vector{S}} where {S}
    size = add !== nothing ? 1 : 0
    for ci in org
        if !ISDEADCI(ci)
            size += 1
        end
    end
    if size != 0
        ncip = S[]
        for ci in org
            if !ISDEADCI(ci)
                if add !== nothing && add.speedup >= ci.speedup
                    push!(ncip, add)
                    add = nothing
                end
                push!(ncip, ci)
            end
        end
        if add !== nothing
            push!(ncip, add)
        end
        @assert length(ncip) == size
        return ncip
    end
    return nothing
end

# PORT: pl-index.c cmp_indexes
"Order of an index array: live before dead, then by decreasing speedup (pl-index.c)."
function cmp_indexes(ci1, ci2)::Int
    if ISDEADCI(ci1)
        if ISDEADCI(ci2)
            return 0
        end
        return 1
    elseif ISDEADCI(ci2)
        return -1
    end
    return if ci1.speedup < ci2.speedup
        1
    elseif ci1.speedup > ci2.speedup
        -1
    else
        0
    end
end

# PORT: pl-index.c sortIndexes
"Sort an index array by `cmp_indexes` (pl-index.c)."
function sortIndexes!(cip)::Nothing
    if cip !== nothing
        sort!(cip; lt=(a, b) -> cmp_indexes(a, b) < 0)
    end
    return nothing
end

# PORT: pl-index.c isSortedIndexes
"True when the live indexes of the array are in decreasing speedup (pl-index.c)."
function isSortedIndexes(cip)::Bool
    if cip !== nothing
        speedup = Float32(typemax(Int64))                              # (float)PLMAXINT
        for ci in cip
            if ISDEADCI(ci)
                continue
            end
            if speedup < ci.speedup
                return false
            end
            speedup = ci.speedup
        end
    end
    return true
end

# PORT: pl-index.c setIndexes
# DIVERGES: the old array is left to the garbage collector (upstream lingers it).
"Install `cip` as the index array of `cl` (pl-index.c)."
function setIndexes!(
    def::Definition{T}, cl::ClauseList{T},
    cip::Union{Nothing, Vector{Union{Nothing, ClauseIndex{T}}}}
)::Nothing where {T}
    cl.clause_indexes = cip
    return nothing
end

# PORT: pl-index.c replaceIndex
# DIVERGES: the slot is `cip[i]` where upstream passes a pointer to it; the old index is left to the
# garbage collector (upstream lingers it).
"Put `ci` (or `DEAD_INDEX`) in slot `i` of `cip`, forgetting the old index's assessments."
function replaceIndex!(
    def::Definition{T}, cl::ClauseList{T}, cip::Vector{Union{Nothing, ClauseIndex{T}}},
    i::Int,
    ci::Union{Nothing, ClauseIndex{T}}
)::Nothing where {T}
    old = cip[i]
    cip[i] = ci
    if !ISDEADCI(old)
        # delete corresponding assessments
        for k in 1:MAX_MULTI_INDEX
            a = old.args[k]
            if a != 0
                ai = (cl.args::Vector{arg_info})[a]
                ai.assessed = false
            end
        end
    end
    if !isSortedIndexes(cl.clause_indexes)
        ncip = copyIndex(cl.clause_indexes::Vector{Union{Nothing, ClauseIndex{T}}}, nothing)
        sortIndexes!(ncip)
        setIndexes!(def, cl, ncip)
    end
    return nothing
end

# PORT: pl-index.c deleteIndexP
"Mark slot `i` of `cip` dead (pl-index.c)."
deleteIndexP!(
    def::Definition{T}, cl::ClauseList{T}, cip::Vector{Union{Nothing, ClauseIndex{T}}},
    i::Int
) where {T} = replaceIndex!(def, cl, cip, i, DEAD_INDEX)

# PORT: pl-index.c deleteIndex
"Mark index `ci` of `clist` dead (pl-index.c)."
function deleteIndex!(
    def::Definition{T}, clist::ClauseList{T}, ci::ClauseIndex{T}
)::Nothing where {T}
    cip = clist.clause_indexes
    if cip !== nothing
        for i in eachindex(cip)
            if cip[i] === ci
                deleteIndexP!(def, clist, cip, i)
                return nothing
            end
        end
    end
    @assert false "deleteIndex!: index not in the clause list"
    return nothing
end

# PORT: pl-index.c next_clause_index
"The first live index in `cip` from slot `i` (pl-index.c)."
function next_clause_index(cip::Vector{S}, i::Int) where {S}
    while i <= length(cip)
        ci = cip[i]
        if !ISDEADCI(ci)
            return ci
        end
        i += 1
    end
    return nothing
end

# PORT: pl-index.c insertIndex
"Insert `add` into the index array of `clist`, reusing a dead slot where the order allows."
function insertIndex!(
    def::Definition{T}, clist::ClauseList{T}, add::ClauseIndex{T}
)::Nothing where {T}
    ocip = clist.clause_indexes
    if ocip !== nothing
        prev::Union{Nothing, ClauseIndex{T}} = nothing
        for i in eachindex(ocip)
            ci = ocip[i]
            if ISDEADCI(ci)
                next = next_clause_index(ocip, i + 1)
                if (prev === nothing || prev.speedup >= add.speedup) &&
                    (next === nothing || next.speedup <= add.speedup)
                    ocip[i] = add
                    return nothing
                end
            else
                prev = ci
            end
        end
        ncip = copyIndex(ocip, add)
        setIndexes!(def, clist, ncip)
    else
        clist.clause_indexes = Union{Nothing, ClauseIndex{T}}[add]
    end
    return nothing
end

# ── ASSESSMENT ──────────────────────────────────────────────────────────────────────────────────
# PORT: pl-index.c key_asm
"One key of an assessment and how often it occurs (pl-index.c `key_asm`)."
struct key_asm
    key::word
    count::UInt32
    nvcomp::UInt32          # compound with arguments
end

# PORT: pl-index.c hash_assessment
# DIVERGES: upstream's `space` field is computed but never read; it is not kept.
"The assessment of one candidate index (pl-index.c `hash_assessment`)."
mutable struct hash_assessment
    args::NTuple{MAX_MULTI_INDEX, iarg_t}   # arg for which to assess
    allocated::Int                          # allocated size of array
    size::Int                               # keys in array
    var_count::Int                          # # non-indexable cases
    funct_count::Int                        # # functor cases
    stdev::Float32                          # Standard deviation
    speedup::Float32                        # Expected speedup
    list::Bool                              # Put lists in the buckets
    keys::Union{Nothing, Vector{key_asm}}   # tmp key-set
end

# PORT: pl-index.c assessment_set
"A set of assessments (pl-index.c `assessment_set`); its count is the vector's length."
struct assessment_set
    assessments::Vector{hash_assessment}
end

# PORT: pl-index.c init_assessment_set
"An empty assessment set (pl-index.c)."
init_assessment_set()::assessment_set = assessment_set(hash_assessment[])

# PORT: pl-index.c alloc_assessment
"Add a zeroed assessment of the arguments `ia` (in canonical form) to `as` (pl-index.c)."
function alloc_assessment!(
    as::assessment_set, ia::NTuple{MAX_MULTI_INDEX, iarg_t}
)::hash_assessment
    a = hash_assessment(canonicalHap(ia), 0, 0, 0, 0, 0.0f0, 0.0f0, false, nothing)
    push!(as.assessments, a)
    return a
end

# PORT: pl-index.c best_hash_assessment
"Order of argument positions by decreasing assessed speedup (pl-index.c)."
function best_hash_assessment(a1::iarg_t, a2::iarg_t, clist::ClauseList{T})::Int where {T}
    args = clist.args::Vector{arg_info}
    i1 = args[Int(a1) + 1]
    i2 = args[Int(a2) + 1]
    return if i1.speedup - i2.speedup > 0.0f0
        -1
    elseif i1.speedup - i2.speedup < 0.0f0
        1
    else
        0
    end
end

# PORT: pl-index.c sort_assessments
# DIVERGES: a stable sort; upstream's sort_r (qsort_r) leaves equal speedups in unspecified order.
"Sort the first `ninstantiated` argument positions by decreasing speedup — best first."
function sort_assessments!(
    clist::ClauseList{T}, instantiated::Vector{iarg_t}, ninstantiated::Int
)::Nothing where {T}
    sort!(
        view(instantiated, 1:ninstantiated);
        lt=(x, y) -> best_hash_assessment(x, y, clist) < 0
    )
    return nothing
end

# PORT: pl-index.c compar_keys
"Order of assessment keys (pl-index.c)."
compar_keys(k1::key_asm, k2::key_asm)::Int = (k1.key > k2.key) - (k1.key < k2.key)

# PORT: pl-index.c perfect_size
"The lg2 of the smallest bucket count (up to 32) giving the keys a hash without collisions."
function perfect_size(a::hash_assessment)::Int
    keys = a.keys::Vector{key_asm}
    ln_buckets = MSB(a.size) & 0x1f
    buckets = 2 << ln_buckets
    while buckets <= 32
        filled = UInt64(0)                                  # local_bitvector(filled, buckets)
        kp = 1
        while kp <= a.size
            i = hashIndex(keys[kp].key, UInt32(buckets))
            bit = UInt64(1) << i
            if (filled & bit) != 0                          # !set_bit(filled, i)
                break
            end
            filled |= bit
            kp += 1
        end
        if kp > a.size
            return ln_buckets
        end
        buckets *= 2
        ln_buckets += 1
    end
    return ln_buckets
end

# PORT: pl-index.c assess_remove_duplicates
# DIVERGES: a stable sort of the keys; upstream's qsort leaves equal keys in unspecified order.
"""
Merge duplicate keys of `a`. Given a `clause_count`, also finish the assessment — speedup,
standard deviation, whether to use a list index — and return false when it is not an index.
"""
function assess_remove_duplicates!(a::hash_assessment, clause_count::Int)::Bool
    a.speedup = 0.0f0
    a.list = false
    if a.keys === nothing
        return false
    end
    keys = a.keys::Vector{key_asm}
    o = 0                               # a->keys-1
    c = word(0)                         # invalid key
    fc = 0                              # #indexable compounds
    i = 0                               # #unique keys
    A = 0.0f0
    Q = 0.0f0
    sort!(view(keys, 1:a.size); lt=(x, y) -> compar_keys(x, y) < 0)
    for s in 1:a.size
        ks = keys[s]
        if ks.key != c
            i0 = i
            i += 1
            if i0 > 0 && clause_count != 0
                ko = keys[o]
                A0 = A
                A = A + (Float32(ko.count) - A) / Float32(i - 1)
                Q = Q + (Float32(ko.count) - A0) * (Float32(ko.count) - A)
                if ko.nvcomp != 0
                    fc += Int(ko.nvcomp) - 1        # no point if there is just one
                end
            end
            c = ks.key
            o += 1
            keys[o] = ks
        else
            ko = keys[o]
            keys[o] = key_asm(ko.key, ko.count + ks.count, ko.nvcomp)
            keys[s] = key_asm(ks.key, ks.count, ks.nvcomp + ks.nvcomp)  # verbatim: `s->nvcomp += s->nvcomp`
        end
    end
    if i > 0 && clause_count != 0
        ko = keys[o]
        A0 = A
        A = A + (Float32(ko.count) - A) / Float32(i)
        Q = Q + (Float32(ko.count) - A0) * (Float32(ko.count) - A)
        if ko.nvcomp != 0
            fc += Int(ko.nvcomp) - 1
        end
        a.funct_count = fc
    end
    a.size = i
    # assess quality
    if clause_count != 0
        a.stdev = Float32(sqrt(Float64(Q / Float32(i))))
        a.list = false
        if a.size == 1                  # Single value that is not compound
            if !isFunctor(keys[1].key)
                return false
            end
        end
        a.speedup =
            Float32(clause_count * a.size) /
            Float32(clause_count - a.var_count + a.var_count * a.size)
        # punish bad distributions
        a.speedup /= 1.0f0 + a.stdev * Float32(a.size) / Float32(clause_count)
        if a.speedup < Float32(clause_count) / MIN_SPEEDUP && a.funct_count > 0 &&
            a.var_count == 0             # See (*)
            a.list = true
        end
        if Float32(a.var_count) / Float32(a.size) > MAX_VAR_FRAC
            a.speedup = 0.0f0
            return false                # not indexable
        end
    end
    return true
end

# PORT: pl-index.c assessAddKey
"Count one occurrence of `key` (`nvcomp`: a compound with non-variable arguments) in `a`."
function assessAddKey!(a::hash_assessment, key::word, nvcomp::Bool)::Bool
    if a.size > 0 && (a.keys::Vector{key_asm})[a.size].key == key
        keys = a.keys::Vector{key_asm}
        k = keys[a.size]
        keys[a.size] = key_asm(k.key, k.count + 1, nvcomp ? k.nvcomp + 1 : k.nvcomp)
    elseif a.size < a.allocated
        _put_key!(a, key, nvcomp)
    else
        if a.allocated == 0
            a.allocated = 512
            a.keys = Vector{key_asm}(undef, a.allocated)
        else
            assess_remove_duplicates!(a, 0)
            if a.size * 2 > a.allocated
                resize!(a.keys::Vector{key_asm}, a.allocated * 2)
                a.allocated *= 2
            end
        end
        _put_key!(a, key, nvcomp)
    end
    return true
end

"`assessAddKey!`'s `put_key:` block."
function _put_key!(a::hash_assessment, key::word, nvcomp::Bool)::Nothing
    keys = a.keys::Vector{key_asm}
    keys[a.size + 1] = key_asm(key, UInt32(1), UInt32(nvcomp))
    a.size += 1
    return nothing
end

# From pl-index.c `skipToTerm` (its `static code var[2]`): the code a deep position inside an
# `H_LIST_FF` reads — both arguments of the list cell are fresh variables, so two voids. Read-only.
const H_LIST_FF_VOIDS = code[H_VOID, H_VOID]

# PORT: pl-index.c skipToTerm
# DIVERGES: returns `(position, in_hvoid)` where upstream updates `*in_hvoid` through a pointer.
"""
The code of the arguments of the compound at deep-index `position` in the head of `clause`; where
the path meets something other than a compound, the code found there (pl-index.c).
"""
function skipToTerm(
    clause::Clause{T}, position::NTuple{MAXINDEXDEPTH + 1, iarg_t}, in_hvoid::Int
)::Tuple{Code{T}, Int} where {T}
    pc = Code(clause, 1)
    for k in 1:(MAXINDEXDEPTH + 1)
        an = Int(position[k])
        an == END_INDEX_POS && break
        if an > 0
            pc, in_hvoid = skipArgs(pc, an, in_hvoid)
        end
        c = decode(pc)
        while c == I_CHP                                    # again:
            pc = stepPC(pc)
            c = decode(pc)
        end
        if c == H_LIST_FF                                   # FF1, FF2
            return (Code{T}(H_LIST_FF_VOIDS, pc.literals, 1), in_hvoid)   # the dummy: two voids
        end
        if !(c == H_FUNCTOR || c == H_LIST || c == H_RFUNCTOR || c == H_RLIST)
            return (pc, in_hvoid)                           # default: return pc
        end
        pc = stepPC(pc)
    end
    return (pc, in_hvoid)
end

# PORT: pl-index.c indexableCompound
"""
True if the compound at `pc` can be indexed: one of its arguments is not a variable. As we
consider a compound indexable, we never go into nested compounds (pl-index.c).
"""
function indexableCompound(pc::Code{T})::Bool where {T}
    while true
        c = decode(pc)
        if c == H_LIST_FF
            return false
        elseif c == I_CHP
            pc = stepPC(pc)
        elseif c == H_FUNCTOR || c == H_RFUNCTOR || c == H_LIST || c == H_RLIST
            pc = stepPC(pc)                                 # skip functor
            while true
                c2 = decode(pc)
                if c2 == H_FIRSTVAR || c2 == H_VAR || c2 == H_VOID || c2 == H_VOID_N
                    pc = stepPC(pc)                         # Try next argument
                elseif c2 == H_POP
                    return false                            # End of argument list
                else
                    return true                             # Indexable
                end
            end
        else
            @assert false "indexableCompound: not a compound"
            return false
        end
    end
end

# PORT: pl-index.c assess_scan_clauses
"Add the keys of every live clause of `clist` to the first `assess_count` assessments."
function assess_scan_clauses!(
    clist::ClauseList{T}, ac::Int, assessments::Vector{hash_assessment}, assess_count::Int,
    ctx::index_context{T}
)::Nothing where {T}
    ai = zeros(Bool, ac)
    # Find the arguments we must check. Assessments may be for multiple arguments.
    for i in 1:assess_count
        a = assessments[i]
        j = 1
        while j <= MAX_MULTI_INDEX && a.args[j] != 0
            ai[a.args[j]] = true                            # set_bit(ai, a->args[j]-1)
            j += 1
        end
    end
    # kp[] is an array of arguments we must check
    kp = Int[]
    for i in 0:(ac - 1)
        if ai[i + 1]
            push!(kp, i)
        end
    end
    keys = zeros(word, ac)
    nvcomp = zeros(Bool, ac)
    # Step through the clause list
    cref = clist.first_clause
    while cref !== nothing
        cl = cref.clause::Clause{T}
        if (cl.flags & CL_ERASED) == 0
            carg = 0
            h_void = 0
            pc, h_void = skipToTerm(cl, ctx.position, h_void)
            # fill keys[i] with the value of arg kp[i]
            for p in kp
                if p > carg
                    pc, h_void = skipArgs(pc, p - carg, h_void)
                end
                carg = p
                keys[p + 1] = argKey(pc, 0)
                nvcomp[p + 1] = false
                # see whether this a compound with nonvar args
                if isFunctor(keys[p + 1])
                    if indexableCompound(pc)
                        nvcomp[p + 1] = true
                    end
                end
            end
            for i in 1:assess_count
                a = assessments[i]
                if a.args[2] == 0                           # single argument index
                    an = Int(a.args[1]) - 1
                    key = keys[an + 1]
                    if key != 0
                        assessAddKey!(a, key, nvcomp[an + 1])
                    else
                        a.var_count += 1
                    end
                else                                        # multi-argument index
                    key = (word(0), word(0), word(0), word(0))
                    harg = 0
                    isvar = false
                    while harg < MAX_MULTI_INDEX && a.args[harg + 1] != 0
                        k = keys[a.args[harg + 1]]
                        if k == 0
                            isvar = true
                            break
                        end
                        key = Base.setindex(key, k, harg + 1)
                        harg += 1
                    end
                    if isvar
                        a.var_count += 1
                    else
                        assessAddKey!(a, join_multi_arg_keys(key, harg), false)
                    end
                end
            end
        end
        cref = cref.next
    end
    return nothing
end

# PORT: pl-index.c best_assessment
"Finish the assessments; the best one above `MIN_SPEEDUP`, or `nothing` (pl-index.c)."
function best_assessment!(
    assessments::Vector{hash_assessment}, count::Int, clause_count::Int
)::Union{Nothing, hash_assessment}
    best::Union{Nothing, hash_assessment} = nothing
    minbest = MIN_SPEEDUP
    for i in 1:count
        a = assessments[i]
        assess_remove_duplicates!(a, clause_count)
        if a.speedup > minbest
            best = a
            minbest = a.speedup
        end
    end
    return best
end

# PORT: pl-index.c assess_candidate_indexes
"Record each assessment of `aset` in `clist.args`: speedup, list, bucket count (pl-index.c)."
function assess_candidate_indexes!(
    ac::Int, clist::ClauseList{T}, aset::assessment_set, ctx::index_context{T}
)::Nothing where {T}
    assess_scan_clauses!(clist, ac, aset.assessments, length(aset.assessments), ctx)
    for a in aset.assessments
        ainfo = (clist.args::Vector{arg_info})[a.args[1]]
        if assess_remove_duplicates!(a, Int(clist.number_of_clauses))
            ainfo.speedup = a.speedup
            ainfo.list = a.list
            ainfo.ln_buckets = (perfect_size(a) & 0x1f) % UInt8
        else
            ainfo.speedup = 0.0f0
            ainfo.list = false
            ainfo.ln_buckets = 0
        end
        ainfo.assessed = true
        a.keys = nothing
    end
    return nothing
end

# PORT: pl-index.c ensure_arg_info
"The per-argument information of `clist`, allocated for `ac` arguments if absent (pl-index.c)."
function ensure_arg_info!(clist::ClauseList{T}, ac::Int)::Vector{arg_info} where {T}
    if clist.args === nothing
        clist.args = [arg_info() for _ in 1:ac]
    end
    return clist.args::Vector{arg_info}
end

# PORT: pl-index.c better_index
"True when `speedup` beats `better_than` by `min_speedup`, or there is nothing to beat."
function better_index(better_than, speedup::Float32, min_speedup::Float32)::Bool
    if better_than !== nothing
        return speedup > better_than.speedup * min_speedup
    end
    return true
end

# PORT: pl-index.c cp_hints_from_arg_info
"Hints for a single-argument index on argument `arg0` (0-based) (pl-index.c)."
function cp_hints_from_arg_info!(hints::hash_hints, arg0::Int, ai::arg_info)::Nothing
    hints.args = ((arg0 + 1) % iarg_t, 0x00, 0x00, 0x00)
    hints.ln_buckets = ai.ln_buckets
    hints.speedup = ai.speedup
    hints.list = ai.list
    return nothing
end

# PORT: pl-index.c cp_hints_from_assessment
"Hints for the index assessment `a` describes (pl-index.c)."
function cp_hints_from_assessment!(hints::hash_hints, a::hash_assessment)::Nothing
    hints.args = a.args
    hints.ln_buckets = (MSB(a.size) & 0x1f) % UInt8
    hints.speedup = a.speedup
    hints.list = a.list
    return nothing
end

# PORT: pl-index.c bestHash
"""
Find the best argument(s) to hash the clauses of `clist` on for the call `av`: assess the
instantiated arguments not assessed before, pick the best single one, and try two-argument indexes
when it is poor. True with the result in `hints` (pl-index.c).
"""
function bestHash!(
    av::A, argc::Int, clist::ClauseList{T}, better_than::Union{Nothing, ClauseIndex{T}},
    hints::hash_hints, ctx::index_context{T}
)::Bool where {T, A}
    best = -1
    best_speedup = 0.0f0
    ia = (0x00, 0x00, 0x00, 0x00)
    ac = argc > MAXINDEXARG ? MAXINDEXARG : argc
    # Step 1: find instantiated args
    instantiated = Vector{iarg_t}(undef, ac)
    ninstantiated = 0
    for i in 0:(ac - 1)
        if canIndex(argv_at(av, i))
            ninstantiated += 1
            instantiated[ninstantiated] = i % iarg_t
        end
    end
    if ninstantiated == 0
        return false
    end
    aset = init_assessment_set()        # Prepare for assessment
    args = ensure_arg_info!(clist, ac)
    # Step 2: find new unassessed args
    for i in 1:ninstantiated
        arg = Int(instantiated[i])
        if !args[arg + 1].assessed
            ia = Base.setindex(ia, (arg + 1) % iarg_t, 1)
            alloc_assessment!(aset, ia)
        end
    end
    if !isempty(aset.assessments)       # Step 3: assess them
        assess_candidate_indexes!(ac, clist, aset, ctx)
    end
    # Step 4: find the best (single) arg
    for i in 1:ninstantiated
        arg = Int(instantiated[i])
        ainfo = args[arg + 1]
        if ainfo.speedup > best_speedup
            best = arg
            best_speedup = ainfo.speedup
        end
    end
    if best >= 0                        # Found at least one index
        if consider_better_index(best_speedup, clist.number_of_clauses) &&
            ninstantiated > 1            # ... but not a real good one ...
            if find_multi_argument_hash!(
                ac, clist, instantiated, ninstantiated, better_than, hints, ctx
            )
                return true
            end
        end
        if better_index(better_than, best_speedup, MIN_SPEEDUP)
            ainfo = args[best + 1]
            cp_hints_from_arg_info!(hints, best, ainfo)
            return true
        end
    end
    return false
end

# PORT: pl-index.c find_multi_argument_hash
"""
Try a two-argument index when every single-argument index is poor; true with the result in
`hints` (pl-index.c). `instantiated` is sorted best-first in place.
"""
function find_multi_argument_hash!(
    ac::Int, clist::ClauseList{T}, instantiated::Vector{iarg_t}, ninstantiated::Int,
    better_than::Union{Nothing, ClauseIndex{T}}, hints::hash_hints, ctx::index_context{T}
)::Bool where {T}
    sort_assessments!(clist, instantiated, ninstantiated)
    args = clist.args::Vector{arg_info}
    ok = 0
    while ok < ninstantiated && args[Int(instantiated[ok + 1]) + 1].speedup > MIN_SPEEDUP
        ok += 1
    end
    if ok >= 2 && Int(clist.jiti_tried) <= ac
        ia = (0x00, 0x00, 0x00, 0x00)
        clist.jiti_tried += 0x01
        aset = init_assessment_set()
        for m in 1:(ok - 1)
            ia = Base.setindex(ia, (Int(instantiated[m + 1]) + 1) % iarg_t, 2)
            for n in 0:(m - 1)
                ia = Base.setindex(ia, (Int(instantiated[n + 1]) + 1) % iarg_t, 1)
                alloc_assessment!(aset, ia)
            end
        end
        assess_scan_clauses!(clist, ac, aset.assessments, length(aset.assessments), ctx)
        nbest = best_assessment!(
            aset.assessments, length(aset.assessments), Int(clist.number_of_clauses)
        )
        if nbest !== nothing && better_index(better_than, nbest.speedup, MIN_SPEEDUP)
            hints.speedup = 0.0f0       # memset(hints, 0, sizeof(*hints))
            hints.list = false
            hints.args = nbest.args
            hints.ln_buckets = (MSB(nbest.size) & 0x1f) % UInt8   # dubious cast
            hints.speedup = nbest.speedup
            return true
        end
    end
    return false
end

# ── FIND CANDIDATE INDEXES ──────────────────────────────────────────────────────────────────────
# PORT: pl-index.c cmp_assessment
"Order of assessments by increasing speedup (pl-index.c)."
cmp_assessment(a1::hash_assessment, a2::hash_assessment)::Int =
    (a1.speedup > a2.speedup) - (a1.speedup < a2.speedup)

# PORT: pl-index.c assess_all_arguments
"Ensure `clist.args[a]` is assessed for every argument below `ac` but mode `-` ones."
function assess_all_arguments!(
    ac::Int, clist::ClauseList{T}, ctx::index_context{T}
)::Nothing where {T}
    aset = init_assessment_set()
    for i in 0:(ac - 1)
        if ctx.depth == 0 && mode_arg_is_unbound(ctx.predicate, i)
            continue
        end
        ai = (clist.args::Vector{arg_info})[i + 1]
        if !ai.assessed
            alloc_assessment!(aset, ((i + 1) % iarg_t, 0x00, 0x00, 0x00))
        end
    end
    assess_candidate_indexes!(ac, clist, aset, ctx)
    return nothing
end

# PORT: pl-index.c create_good_indexes
# DIVERGES: returns (number of assessments consumed, new hint count) where upstream returns the
# first and writes the second through `nphints`.
"Hints for the good single-argument indexes, best first (pl-index.c)."
function create_good_indexes!(
    clist::ClauseList{T}, assessments::AbstractVector{iarg_t}, nassessments::Int,
    hints::Vector{hash_hints}, nhints::Int, max_hints::Int
)::Tuple{Int, Int} where {T}
    args = clist.args::Vector{arg_info}
    i = 0
    while i < nassessments && nhints < max_hints
        arg0 = Int(assessments[i + 1])
        ai = args[arg0 + 1]
        if Float32(clist.number_of_clauses) / ai.speedup < MIN_SPEEDUP
            if clist.number_of_clauses > MIN_CLAUSES_FOR_INDEX ||
                Int(clist.primary_index) != arg0
                nhints += 1
                cp_hints_from_arg_info!(hints[nhints], arg0, ai)
            end
        else
            break
        end
        i += 1
    end
    return (i, nhints)
end

# PORT: pl-index.c create_deep_indexes
# DIVERGES: returns (assessments kept, new hint count) where upstream writes them through pointers.
"Hints for the list (deep) indexes; keeps the remaining assessments above `MIN_SPEEDUP`."
function create_deep_indexes!(
    clist::ClauseList{T}, assessments::AbstractVector{iarg_t}, nassessments::Int,
    hints::Vector{hash_hints}, nhints::Int, max_hints::Int
)::Tuple{Int, Int} where {T}
    args = clist.args::Vector{arg_info}
    keep = 0
    for i in 1:nassessments
        arg0 = Int(assessments[i])
        ai = args[arg0 + 1]
        if ai.list && nhints < max_hints
            nhints += 1
            cp_hints_from_arg_info!(hints[nhints], arg0, ai)
        elseif ai.speedup > MIN_SPEEDUP
            keep += 1
            assessments[keep] = arg0 % iarg_t
        end
    end
    return (keep, nhints)
end

# PORT: pl-index.c candidate_indexes
# DIVERGES: returns (true, number of hints) where upstream writes the count through `nphints`.
"""
Find all candidate indexes of `clist`: the good single-argument ones, the list (deep) ones, and
two-argument ones better than `MIN_SPEEDUP` times the arguments they combine, merged by speedup
(pl-index.c).
"""
function candidate_indexes!(
    ac::Int, clist::ClauseList{T}, hints::Vector{hash_hints}, max_hints::Int,
    ctx::index_context{T}
)::Tuple{Bool, Int} where {T}
    nhints = 0
    # Assess all non-yet-assessed arguments
    assess_all_arguments!(ac, clist, ctx)
    # Sort by quality
    args = clist.args::Vector{arg_info}
    all_assessments = Vector{iarg_t}(undef, ac)
    nassessments = 0
    for i in 0:(ac - 1)
        ai = args[i + 1]
        if ai.assessed && (ai.speedup > MIN_SPEEDUP || ai.list)
            nassessments += 1
            all_assessments[nassessments] = i % iarg_t
        end
    end
    if nassessments == 0
        return (true, 0)
    end
    sort_assessments!(clist, all_assessments, nassessments)
    # Create the good ones. They are best and need not be combined
    good, nhints = create_good_indexes!(
        clist, all_assessments, nassessments, hints, nhints, max_hints
    )
    if nhints == max_hints
        return (true, nhints)
    end
    assessments = view(all_assessments, (good + 1):nassessments)      # assessments += good
    nassessments -= good
    # Create the poor deep indexes and remove the other poor ones
    nassessments, nhints = create_deep_indexes!(
        clist, assessments, nassessments, hints, nhints, max_hints
    )
    if nhints == max_hints
        return (true, nhints)
    end
    if nassessments >= 2                # Add least two candidates
        f = 0
        t = nassessments
        ia = (0x00, 0x00, 0x00, 0x00)
        while true                      # If far too many, take the middle ones
            l1 = t - f                  # as these are the most promising
            if l1 < 2
                return (true, nhints)
            end
            l1 -= 1
            if l1 * l1 > max_hints - nhints
                if f % 2 == 0
                    f += 1
                else
                    t -= 1
                end
            else
                break
            end
        end
        aset = init_assessment_set()
        for m in (f + 1):(t - 1)
            ia = Base.setindex(ia, (Int(assessments[m + 1]) + 1) % iarg_t, 2)
            for n in f:(m - 1)
                ia = Base.setindex(ia, (Int(assessments[n + 1]) + 1) % iarg_t, 1)
                alloc_assessment!(aset, ia)
            end
        end
        assess_scan_clauses!(clist, ac, aset.assessments, length(aset.assessments), ctx)
        alist = hash_assessment[]
        for a in aset.assessments
            poor = false
            assess_remove_duplicates!(a, Int(clist.number_of_clauses))
            for j in 1:2
                ai = args[a.args[j]]
                if a.speedup < ai.speedup * MIN_SPEEDUP
                    poor = true
                    break
                end
            end
            if !poor
                push!(alist, a)
            end
        end
        # DIVERGES: a stable sort; upstream's qsort leaves equal speedups in unspecified order.
        sort!(alist; lt=(x, y) -> cmp_assessment(x, y) < 0)
        # merge single and multiple argument indexes by speedup
        ap = 1
        single = 0
        while nhints < max_hints
            if single < nassessments
                si = Int(assessments[single + 1])
                # skip the primary index
                if clist.number_of_clauses <= MIN_CLAUSES_FOR_INDEX &&
                    Int(clist.primary_index) == si
                    single += 1
                    continue
                end
                ai = args[si + 1]
                if ap <= length(alist)
                    if alist[ap].speedup > ai.speedup
                        nhints += 1
                        cp_hints_from_assessment!(hints[nhints], alist[ap])
                        ap += 1
                    else
                        nhints += 1
                        cp_hints_from_arg_info!(hints[nhints], si, ai)
                        single += 1
                    end
                else
                    nhints += 1
                    cp_hints_from_arg_info!(hints[nhints], si, ai)
                    single += 1
                end
            elseif ap <= length(alist)
                nhints += 1
                cp_hints_from_assessment!(hints[nhints], alist[ap])
                ap += 1
            else
                break
            end
        end
    end
    return (true, nhints)
end

# PORT: pl-index.c get_existing_index
# DIVERGES: returns (index, next slot to search) where upstream advances `*from` through a pointer.
"The live index of `org`, from slot `from`, over the arguments `hints` name (pl-index.c)."
function get_existing_index(org, from::Int, hints::hash_hints)
    if org !== nothing
        i = from
        while i <= length(org)
            ci = org[i]
            if !ISDEADCI(ci)
                if ci.args == hints.args
                    return (ci, i + 1)
                end
            end
            i += 1
        end
    end
    return (nothing, from)
end

# PORT: pl-index.c set_candidate_indexes
# DIVERGES: no locking (`lock` is kept for the signature; there are no threads).
"""
Set the candidate indexes of a static predicate: every meaningful index, NOT yet realised (each is
filled the first time a call can use it), and stop searching for others (pl-index.c).
"""
function set_candidate_indexes!(
    def::Definition{T}, clist::ClauseList{T}, max::Int, lock::Bool
)::Bool where {T}
    hints = [hash_hints() for _ in 1:max]
    ctx = index_context{T}(gen_t(0), def, nothing, 0, _TOP_POSITION, false)
    ac = def.arity > MAXINDEXARG ? MAXINDEXARG : def.arity
    _, max = candidate_indexes!(ac, clist, hints, max, ctx)
    if max > 0
        cip = Vector{Union{Nothing, ClauseIndex{T}}}(undef, max)
        org = clist.clause_indexes
        from = 1
        for i in 1:max
            ei, from = get_existing_index(org, from, hints[i])
            if ei !== nothing
                cip[i] = ei
            else
                cip[i] = newClauseIndexTable(hints[i], false, ctx)
            end
        end
        setIndexes!(def, clist, cip)
        clist.fixed_indexes = true
    else
        clist.fixed_indexes = true
    end
    return true
end

# ── THE PRIMARY INDEX ───────────────────────────────────────────────────────────────────────────
# PORT: pl-index.c PINDEX_POSSIBLE
"`can_be_primary_index`: the argument discriminates (pl-index.c)."
const PINDEX_POSSIBLE = 0
# PORT: pl-index.c PINDEX_IMPOSSIBLE
"No meaningful indexing possible (pl-index.c)."
const PINDEX_IMPOSSIBLE = -1
# PORT: pl-index.c PINDEX_MAYBEDEEP
"Some argument has the same functor in every clause — maybe a deep index (pl-index.c)."
const PINDEX_MAYBEDEEP = -2

# PORT: pl-index.c can_be_primary_index
"Whether argument `arg0` (0-based) of the clauses of `clist` can serve as the primary index."
function can_be_primary_index(clist::ClauseList{T}, arg0::Int)::Int where {T}
    first = true
    key = word(0)
    cref = clist.first_clause
    while cref !== nothing
        cl = cref.clause::Clause{T}
        if (cl.flags & CL_ERASED) == 0
            clkey = argKey(Code(cl, 1), arg0)
            if first
                first = false
                key = clkey
            elseif key != clkey
                return PINDEX_POSSIBLE
            end
        end
        cref = cref.next
    end
    if !first && isFunctor(key)
        return PINDEX_MAYBEDEEP
    end
    return PINDEX_IMPOSSIBLE
end

# PORT: pl-index.c preferred_primary_index
"""
The argument to use as primary index (0-based), or `PINDEX_IMPOSSIBLE`, or `PINDEX_MAYBEDEEP` when
some argument holds the same functor in every clause (pl-index.c).
"""
function preferred_primary_index(def::Definition{T})::Int where {T}
    clist = def.impl_clauses
    rc = PINDEX_IMPOSSIBLE
    # is primary index ok?
    if !mode_arg_is_unbound(def, Int(clist.primary_index))
        first = true
        key = word(0)                   # Keep compiler happy
        cref = clist.first_clause
        while cref !== nothing
            if ((cref.clause::Clause{T}).flags & CL_ERASED) == 0
                if first
                    first = false
                    key = cref.key
                elseif key != cref.key
                    return Int(clist.primary_index)
                end
            end
            cref = cref.next
        end
        if !first && isFunctor(key)
            rc = PINDEX_MAYBEDEEP
        end
    end
    for a in 0:(def.arity - 1)
        if a != Int(clist.primary_index) && !mode_arg_is_unbound(def, a)
            c = can_be_primary_index(clist, a)
            if c == PINDEX_POSSIBLE
                return a
            end
            if c == PINDEX_MAYBEDEEP
                rc = PINDEX_MAYBEDEEP
            end
        end
    end
    return rc
end

# PORT: pl-index.c modify_primary_index_arg
"Re-key the clauses of `def` on argument `an` (0-based) and make it the primary index."
function modify_primary_index_arg!(def::Definition{T}, an::Int)::Nothing where {T}
    clist = def.impl_clauses
    if Int(clist.primary_index) != an
        cref = clist.first_clause
        while cref !== nothing
            cl = cref.clause::Clause{T}
            cref.key = argKey(Code(cl, 1), an)
            cref = cref.next
        end
        clist.primary_index = an % iarg_t
        clist.unindexed = false
    end
    return nothing
end

# PORT: pl-index.c update_primary_index
"""
Choose the primary index of a small static predicate — the argument `cref.key` holds, used for the
linear scan instead of a hash table (pl-index.c). Upstream calls it when it sets the predicate's
supervisor, before the first call.
"""
function update_primary_index!(def::Definition{T})::Nothing where {T}
    clist = def.impl_clauses
    if clist.pindex_verified
        return nothing
    end
    clist.pindex_verified = true
    if def.arity > 0
        noc = clist.number_of_clauses
        if noc < MIN_CLAUSES_FOR_INDEX &&
            (def.flags & (P_DYNAMIC | P_MULTIFILE | P_THREAD_LOCAL | P_FOREIGN)) == 0 &&
            !STATIC_RELOADING(def)
            arg0 = Int(clist.primary_index)
            argn = preferred_primary_index(def)
            if argn >= 0
                if argn != arg0
                    modify_primary_index_arg!(def, argn)
                end
            else
                if argn == PINDEX_MAYBEDEEP
                    set_candidate_indexes!(def, clist, 10, false)
                end
                clist.unindexed = clist.clause_indexes === nothing
            end
        end
    else
        clist.unindexed = true
    end
    return nothing
end

# ── PREDICATE PROPERTY SUPPORT: `indexed(L)` ────────────────────────────────────────────────────
"""
One element of `predicate_property(P, indexed(L))` — the keys of the dict upstream's
`unify_clause_index` builds, but `size` (bytes of C structs, meaningless here).
"""
struct index_property
    arguments::Vector{Int}      # list of arguments hashed
    position::Vector{Int}       # argument nesting; [] is a toplevel index
    buckets::Int                # # buckets of the hash
    speedup::Float32            # expected speedup
    list::Bool                  # has sub indexes
    realised::Bool              # the index is realised
    collisions::Int             # buckets that represent multiple keys
end

# PORT: pl-index.c collisionCount
"The number of buckets of a realised index that hold several keys (pl-index.c)."
function collisionCount(ci::clause_index)::Int
    cc = 0
    if ci.entries !== nothing
        for bkt in ci.entries
            if bkt.head !== nothing && bkt.key == 0
                cc += 1
            end
        end
    end
    return cc
end

# PORT: pl-index.c unify_clause_index
# DIVERGES: returns the dict's values as an `index_property` instead of unifying a Prolog dict.
"The `indexed` property entry of index `ci` (pl-index.c)."
function unify_clause_index(ci::clause_index)::index_property
    arguments = Int[]
    for a in ci.args                    # put_args()
        a == 0 && break
        push!(arguments, Int(a))
    end
    position = Int[]
    for p in ci.position
        p == END_INDEX_POS && break
        push!(position, Int(p) + 1)
    end
    return index_property(
        arguments, position, Int(ci.buckets), ci.speedup, ci.is_list,
        ci.entries !== nothing, collisionCount(ci)
    )
end

# PORT: pl-index.c add_deep_indexes
"Append the indexes of the clause lists of list index `ci`, recursively (pl-index.c)."
function add_deep_indexes!(out::Vector{index_property}, ci::ClauseIndex{T})::Bool where {T}
    if ci.entries === nothing
        return true
    end
    for bkt in ci.entries::Vector{ClauseBucket{T}}
        cref = bkt.head
        while cref !== nothing
            if isFunctor(cref.key)
                cl = cref.clauses::ClauseList{T}
                cip = cl.clause_indexes
                if cip !== nothing
                    for dci in cip
                        if ISDEADCI(dci)
                            continue
                        end
                        push!(out, unify_clause_index(dci))
                        if dci.is_list
                            add_deep_indexes!(out, dci)
                        end
                    end
                end
            end
            cref = cref.next
        end
    end
    return true
end

# PORT: pl-index.c unify_index_pattern
# DIVERGES: returns the list (`nothing` where upstream fails: no index) instead of unifying it.
"""
    unify_index_pattern(def) -> Union{Nothing, Vector{index_property}}

`predicate_property(P, indexed(L))`: every live index of `def`, deep ones after the list index
holding them; `nothing` when `def` has none (pl-index.c).
"""
function unify_index_pattern(
    def::Definition{T}
)::Union{Nothing, Vector{index_property}} where {T}
    out = index_property[]
    found = 0
    cip = def.impl_clauses.clause_indexes
    if cip !== nothing
        for ci in cip
            if ISDEADCI(ci)
                continue
            end
            found += 1
            push!(out, unify_clause_index(ci))
            if ci.is_list
                add_deep_indexes!(out, ci)
            end
        end
    end
    return found != 0 ? out : nothing
end
