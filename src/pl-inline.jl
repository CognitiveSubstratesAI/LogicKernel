# UPSTREAM: swipl-devel src/pl-inline.h @ 8609e216cab9
# UPSTREAM: swipl-devel src/pl-incl.h @ 8609e216cab9
# UPSTREAM: swipl-devel src/pl-data.h @ 8609e216cab9
# CLASS: code
# COPYRIGHT: Copyright (c)  2008-2024, University of Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# SWI-Prolog's inline helpers the clause store uses: the bit scan behind bucket counts, the
# cleaning of hashed index keys, clause visibility in a generation, and the database generation —
# and the binding primitives the unifier (src/pl-prims.jl) is built on: `Trail` (pl-inline.h),
# `Mark` and `Undo` (pl-incl.h macros) and `deRef` (a pl-data.h macro). They take the local data
# explicitly, so they are defined here, after it (src/pl-global.jl), rather than in pl-incl.jl.
# Transactions are not ported: where upstream asks "inside a transaction on a P_TRANSACT
# predicate?", the answer here is always no.

# PORT: pl-inline.h MSB
"Index of the most significant set bit: `MSB(1) == 0`, `MSB(2) == 1` (pl-inline.h)."
MSB(i::Integer)::Int = 63 - leading_zeros(UInt64(i))

# PORT: pl-inline.h consPtr
# DIVERGES: `p` is a 1-based POSITION in the stack the storage bits of `ts` name (`STG_GLOBAL` the
# global stack, `STG_LOCAL` the local stack), where upstream's is an address (`ptr2word`).
"The word pointing at position `p` with tag and storage `ts` (pl-inline.h)."
consPtr(p::Int, ts::word)::word = (UInt64(p) << LMASK_BITS) | ts
# PORT: pl-inline.h valPtr
# DIVERGES: the POSITION `w` points at (see `consPtr`), in the stack its storage bits name.
"The position word `w` points at (pl-inline.h)."
valPtr(w::word)::Int = Int(w >> LMASK_BITS)
# PORT: pl-data.h makeRefG
"A reference to position `p` of the global stack (pl-data.h)."
makeRefG(p::Int)::word = consPtr(p, TAG_REFERENCE | STG_GLOBAL)
# PORT: pl-data.h makeRefLok
"A reference to position `p` of the local stack (pl-data.h)."
makeRefLok(p::Int)::word = consPtr(p, TAG_REFERENCE | STG_LOCAL)
# PORT: pl-data.h unRef
"The position a reference word points at (pl-data.h)."
unRef(w::word)::Int = valPtr(w)

# PORT: pl-inline.h fetchAtomArray
# DIVERGES: the table is an argument (`GD->atoms`); block `idx` is `array[idx + 1]`, indexed from 1
# (upstream offsets each block's pointer so `blocks[idx][index]` is direct).
"The atom at `index` in the table `atoms` (pl-inline.h)."
function fetchAtomArray(atoms::atoms_t, index::Int)::atom
    idx = MSB(index)
    return (atoms.array[idx + 1]::Vector{atom})[index - (1 << idx) + 1]
end

# PORT: pl-inline.h fetchFunctorArray
# DIVERGES: the table is an argument (`GD->functors`); block `idx` is `array[idx + 1]`, from 1.
"The functor definition at `index` in the table `functors` (pl-inline.h)."
function fetchFunctorArray(functors::functors_t, index::Int)::functorDef
    idx = MSB(index)
    b = functors.array[idx + 1]::Vector{Union{Nothing, functorDef}}
    return b[index - (1 << idx) + 1]::functorDef
end

# PORT: pl-inline.h clean_index_key
"A hashed key that is never 0 and never reads as a functor (pl-inline.h)."
function clean_index_key(key::word)::word
    key &= ~STG_GLOBAL
    if key == 0
        key = word(1)
    end
    return key
end

# PORT: pl-inline.h visibleClause
# DIVERGES: the reload and transaction cases are not ported (neither exists yet); this is
# upstream's core test, `c <= gen && e > gen`.
"True when clause `cl` is visible in generation `gen` (pl-inline.h)."
function visibleClause(cl::clause, gen::gen_t)::Bool
    c = cl.generation_created
    e = cl.generation_erased
    if c <= gen && e > gen
        return true
    end
    return false
end

# PORT: pl-inline.h visibleClauseCNT
# DIVERGES: the erased-skipped statistic is not kept.
"`visibleClause`, counting the misses upstream (pl-inline.h)."
visibleClauseCNT(cl::clause, gen::gen_t)::Bool = visibleClause(cl, gen)

# PORT: pl-inline.h global_generation
"The generation of the database (pl-inline.h)."
global_generation(gd::PL_global_data)::gen_t = gd._generation

# PORT: pl-inline.h current_generation
# DIVERGES: no transactions — always the global generation.
"The generation a call of `def` runs in (pl-inline.h)."
current_generation(gd::PL_global_data{T}, def::Definition{T}) where {T} =
    global_generation(gd)

# PORT: pl-inline.h next_generation
# DIVERGES: no transactions — always the next global generation — and no `L_GENERATION` lock (no
# threads). Upstream's database starts at generation 1 (`setupProlog` calls it), the kernel's at 0
# (`gen_t(0)`, src/pl-global.jl): not observable from Prolog. (The assert and retract paths increment
# the generation inline, as upstream's do.)
"Advance the database generation; the new generation (pl-inline.h)."
function next_generation!(gd::PL_global_data{T}, def::Definition{T})::gen_t where {T}
    gd._generation += 1
    return gd._generation
end

# PORT: pl-inline.h max_generation
# DIVERGES: no transactions — always `GEN_MAX`.
"The erased generation of a live clause of `def` (pl-inline.h)."
max_generation(def::definition)::gen_t = GEN_MAX

# PORT: pl-inline.h setGenerationFrame
# DIVERGES: two forms. On a frame (`fr`, an index), upstream's: the frame's `generation` becomes the
# current global generation. Without one — `retract/1`, which has no frame until V9 makes it a
# foreign predicate — the generation is returned for the caller to run in. No transactions, so never
# the transaction's generation (`P_TRANSACT`, inl:733-736).
"The generation a frame of `def` is (re)set to: the current global generation (pl-inline.h)."
function setGenerationFrame(gd::PL_global_data{T}, def::Definition{T})::gen_t where {T}
    gen = global_generation(gd)
    while gen != global_generation(gd)              # do … while(): no other thread can move it
        gen = global_generation(gd)
    end
    return gen
end
function setGenerationFrame(
    gd::PL_global_data{T}, ld::PL_local_data{T}, fr::Int
)::Nothing where {T}
    f = ld.frames[fr]
    gen = global_generation(gd)
    while gen != global_generation(gd)              # do … while()
        gen = global_generation(gd)
    end
    f.generation = gen                              # setGenerationFrameVal(fr, gen)
    return nothing
end

# PORT: pl-inline.h QueryFromQid
# DIVERGES: a query handle is the query frame's POSITION (decision 1); the record is found on the
# chain of open queries from `LD->query` (since V3), where upstream computes its address from
# the handle's offset. A handle that names no open query gives 0 — upstream's would point at a
# closed (`QID_CMAGIC`) or reused frame.
"The open query frame (an index) whose handle is `qid`, or 0 (pl-inline.h)."
function QueryFromQid(ld::PL_local_data{T}, qid::Int)::Int where {T}
    qf = ld.query
    while qf != 0
        q = ld.queries[qf]
        q.base == qid && return qf
        qf = q.parent
    end
    return 0
end

# PORT: pl-incl.h QidFromQuery
"The handle of query frame `qf` (pl-incl.h): its position."
QidFromQuery(ld::PL_local_data{T}, qf::Int) where {T} = ld.queries[qf].base

# PORT: pl-incl.h pushArgumentStack
# DIVERGES: an entry is an `argstack_entry` (src/pl-incl.jl). Growth is `f_pushArgumentStack`'s.
"Push `e` on the argument stack (pl-incl.h)."
function pushArgumentStack(ld::PL_local_data{T}, e::argstack_entry{T})::Nothing where {T}
    if ld.aTop < length(ld.astack)                  # aTop+1 < aMax
        ld.aTop += 1
        ld.astack[ld.aTop] = e                      # *aTop++ = (p)
    else
        f_pushArgumentStack(ld, e)
    end
    return nothing
end

# ── bindings: deRef, Trail, Mark, Undo ───────────────────────────────────────────────────────────
# ORIGINAL: the two kinds of variable (L1a; src/pl-global.jl `CELL_KEY_TAG`).
"""
The position of the live cell variable `key` names on this engine's global stack, or 0: the key of
a KEYED variable (a caller's, a counter's, another engine's, or a cell's whose position was reused).
"""
@inline function _cell_pos(ld::PL_local_data, key::UInt64)::Int
    (key & CELL_KEY_TAG) == CELL_KEY_TAG || return 0
    p = Int(key & CELL_POS_MASK)
    return (1 <= p <= ld.gTop && ld.gkey[p] == key && !_is_box(ld, p)) ? p : 0
end

# ORIGINAL: the key of the cell variable at a position (L1a: `gkey`), for the readers that build
# its variable term from a word (`slotValue`, the trail's readers).
"The key of the cell variable at global position `p`."
@inline _cell_key(ld::PL_local_data, p::Int)::UInt64 = ld.gkey[p]

# ORIGINAL — THE COUNTED ADAPTER FOR VARIABLES (L1c sub-commit 6; the L1c plan's condition 3): the
# variable TERM of the cell at a position, made ON DEMAND from the cell's key, for a reader that
# does not work on words (the FLI, the built-ins, the writer, the term-level algorithms). COUNTED
# in `cold_vars` on every call: the zero-export test asserts the VM's hot path never asks (nreverse
# and qsort, test/core_lang/test_zero_exports.jl). Until sub-commit 6 the term was made per cell at
# allocation (`gvars`), whether any reader wanted it or not — 1606 of nreverse's 1621 allocations.
# A variable is its KEY, never its Julia object (src/term_interface.jl): two reads are one variable
# (test/core_lang/test_var_identity.jl). Transitional, with `gkey` (the stamp falls at L1f).
"The variable term of the cell at global position `p` (the counted adapter)."
@inline function _cell_var(ld::PL_local_data{T}, p::Int)::T where {T}
    ld.cold_vars += 1
    return mk_var(T, ld.gkey[p])
end

# ORIGINAL: a value table's box (L1b stage C2) holds the word of its own entry, whose box is here —
# so a retained key at a position a box now occupies names no cell (a cell's word names an entry
# boxed elsewhere, or is 0).
"Whether position `p` of the global stack is a value-table box."
@inline function _is_box(ld::PL_local_data, p::Int)::Bool
    w = ld.gstack[p]
    tagex(w) == (TAG_COMPOUND | STG_RESERVED) || return false
    i = valPtr(w)
    return i <= length(ld.vbox) && ld.vbox[i] == p
end

# ORIGINAL: the value table (L1b stage C2; src/pl-global.jl): a value with no word form yet, held
# by entry, pinned by a box word on the global stack so `Undo!` truncates the table with `gTop`.
"The word of a new value-table entry holding `v`; its box is the next word of the global stack."
@inline function _vword!(ld::PL_local_data{T}, v::T)::word where {T}
    p = ld.gTop + 1
    p > length(ld.gstack) && _growGlobalStack!(ld, p)
    push!(ld.vtable, v)
    push!(ld.vbox, p)
    w = consPtr(length(ld.vtable), TAG_COMPOUND | STG_RESERVED)
    ld.gstack[p] = w                  # the box: the entry's own word (`_cell_pos` tells it apart)
    ld.gTop = p
    return w
end

# ORIGINAL: the exception the L1 plan §2c names (user, 2026-10-14): an atom holding the character 0
# cannot leave the engine as an interface symbol (a Julia `Symbol` cannot hold 0).
"""
    AtomNotRepresentableError(codes)

An atom whose text holds the character 0 was asked for as an interface symbol, which cannot hold it
(atoms stay `Symbol` at the boundary: user, 2026-10-14). `codes` are the atom's code points.
"""
struct AtomNotRepresentableError <: Exception
    codes::Vector{UInt32}
end

# ORIGINAL: a symbol's atom in a database's table (L1b stage C3; src/pl-global.jl `atoms`) — by its
# text: `textToAtom` for a text atom (canonical: one atom per text), `lookupBlob(…,
# reserved_symbol)` for a reserved symbol (`[]` is not the text atom `'[]'`) — its symbol recorded
# in the database's store (`atom_symbols`, L1b C6b), so every engine on that database reads the
# word back. The compiler's entry (an atom operand's word, C6b); an engine goes through its cache.
"The atom word of the symbol `v` in the atom table `atoms`, its symbol recorded in `syms`."
function _atom_word!(atoms::atoms_t, syms::atom_symbols{T}, v::T)::word where {T}
    s = sym_text(v)
    bytes = Vector{UInt8}(codeunits(s))
    w = if is_reserved_symbol(v)
        first(lookupBlob(atoms, bytes, length(bytes), reserved_symbol))
    else
        textToAtom(atoms, PL_chars_t(bytes, length(s), ENC_UTF8, false))
    end
    i = indexAtom(w)
    atomSymbol(syms, i) === nothing && setAtomSymbol!(syms, i, v)
    return w
end

# ORIGINAL: per-engine cache of GD's lookupAtom (`atom_words`, sym_key → atom word) — a CACHE, not a
# second table (user, 2026-10-15): upstream goes straight to the `GD->atoms` hash table. Correct by
# construction, one atom per text: a miss falls through to the database's table and finds the atom
# any engine made, never a second one. Kept while no profile shows it mattering.
"The atom word of the symbol `v` in the engine's atom table (its database's)."
function _atom_word!(ld::PL_local_data{T}, v::T)::word where {T}
    k = sym_key(v)
    w = get(ld.atom_words, k, word(0))
    w != 0 && return w
    w = _atom_word!(ld.atoms, ld.atom_symbols, v)
    ld.atom_words[k] = w
    return w
end

# ORIGINAL: an atom word's interface symbol (L1b stage C3), from the DATABASE's store (C6b). Every
# atom word that reaches a cell or a clause's code comes from `_atom_word!`, which records the
# symbol, so a miss is an error: an atom holding the character 0 (planted: no binding can make one
# yet — it raises `AtomNotRepresentableError`), or a broken invariant. The miss builds its error
# inside the `throw`, so the read itself allocates nothing (`deRef` stays allocation-free).
"The interface symbol of the atom word `w`."
function _atom_value(ld::PL_local_data{T}, w::word)::T where {T}
    v = atomSymbol(ld.atom_symbols, indexAtom(w))
    v === nothing || return v
    throw(_atom_value_error(ld, w))
end

# ORIGINAL: the error of an atom word with no cached symbol (`_atom_value`).
"`AtomNotRepresentableError` for an atom holding the character 0; else an internal error."
@noinline function _atom_value_error(ld::PL_local_data, w::word)::Exception
    a = atomValue(ld.atoms, w)
    codes = if a.type === ucs_atom
        UInt32[reinterpret(UInt32, view(a.name, 1:(a.length)))...]
    else
        UInt32[a.name[j] for j in 1:(a.length)]
    end
    any(iszero, codes) && return AtomNotRepresentableError(codes)
    return ErrorException(
        "atom word $(repr(w)) has no recorded symbol: every atom word in a cell or a clause comes from _atom_word!"
    )
end

# ORIGINAL: the ONE place that tells a live cell variable from a keyed one (L1c: `_slot_store!`,
# `_word_of!` and the cold import read it, so the stamp machinery has one site here).
"The reference word of `v`'s cell when `v` is a live cell variable (`makeRefG`), else 0."
@inline function _var_ref_word(ld::PL_local_data{T}, v::T)::word where {T}
    kind(v) === VAR || return word(0)
    p = _cell_pos(ld, var_key(v))
    return p == 0 ? word(0) : makeRefG(p)
end

# ORIGINAL: a value's word on the global stack (L1b C3): an atom its own word, a compound a copy on
# the stack (L1c: `_compound_word!`, the cold import), a live cell variable a reference to its cell
# (L1c: upstream's `makeRefG`), anything else (for now) a value-table entry
# (`_vword!`) — small integers too, since building a term back from `consInt` would allocate on
# every read until the instructions read words (L1d).
"The word that holds `v` in a cell."
@inline function _word_of!(ld::PL_local_data{T}, v::T)::word where {T}
    k = kind(v)
    k === SYM && return _atom_word!(ld, v)
    k === EXPR && return _compound_word!(ld, v)
    if k === VAR                                    # a live cell variable: its reference (L1c)
        r = _var_ref_word(ld, v)
        r != 0 && return r
    end
    return _vword!(ld, v)
end

# ── compounds on the global stack (L1c; the workspace's L1_plan/stageL1c_design.md) ─────────────
# A compound is its functor word at position `p` and its arguments at `p+1 … p+n`, referenced by
# `consPtr(p, TAG_COMPOUND|STG_GLOBAL)` (pl-data.h). A `$expr/n` compound (Q2) has the reserved
# `$expr` as its functor's name and ALL its children as arguments.
"Whether `w` references a compound on the global stack (pl-data.h `isTerm` with `STG_GLOBAL`)."
@inline _is_gcompound(w::word)::Bool = tagex(w) == (TAG_COMPOUND | STG_GLOBAL)

# ORIGINAL: upstream's in-place layout (pl-vmi.c B_RFUNCTOR: `*ARGP++ = f; setVar(*ap++)…; gTop =
# ap`) as one call: the functor word and `n` unbound arguments at `gTop`.
"Lay out a compound of functor word `f` with `n` unbound arguments on the global stack; its position."
@inline function _alloc_compound!(ld::PL_local_data, f::word, n::Int)::Int
    p = allocGlobalCells!(ld, 1 + n)
    ld.gstack[p] = f
    return p
end

# ORIGINAL — THE COLD EXPORT (L1c; user, 2026-10-15): the compound at global position `p` as an
# interface TERM, for a reader that does not work on words yet (the FLI, the built-ins, the writer).
# COUNTED in `cold_exports` — every call. ONE term per compound, kept in `gterms[p]` until `gTop`
# falls below it (`_truncate_gterms!`, beside the value table's truncation): the term-level
# algorithms that are not over
# cells yet (`do_unify`'s cycle links, the occurs check's marks, compare, copy_term, the writer)
# recognise a compound they revisit by its term's IDENTITY — a fresh term per read would make a
# cyclic structure (`X = f(X), Y = f(Y), X = Y`) never terminate. Transitional: it goes when those
# readers work on the cells (L1d, L1f) — see the workspace's L1_plan/stageL1c_design.md.
# ONE LEVEL DEEP and IMMUTABLE: the head symbol (none for `$expr`), then per argument THE CELL'S
# VARIABLE TERM, which the reader dereferences (`deRef`: the cell's word now — an atom, a value, a
# reference, again this export for a compound). So the term stays right as the cells are bound and
# undone (a memoized `f(a)` would outlive the `Undo` of its argument's binding), a cyclic structure
# never loops it, and a variable keeps its identity (its key).
"The compound at global position `p` as a term (the cold export, counted)."
function _compound_term(ld::PL_local_data{T}, p::Int)::T where {T}
    ld.cold_exports += 1
    m = ld.gterms[p]
    m === nothing || return m
    f = ld.gstack[p]
    while isRef(f)              # linked by a running do_unify_cells (pl-prims.c linkTermsCyclic):
        f = ld.gstack[unRef(f)]  # the compound it is being unified with has the functor word
    end
    n = arityFunctor(ld.functors, f)
    name = nameFunctor(ld.functors, f)
    expr = name == ld.atom_dexpr
    kids = Vector{T}(undef, expr ? n : n + 1)
    k = 0
    if !expr
        kids[1] = _atom_value(ld, name)
        k = 1
    end
    for i in 1:n
        kids[k + i] = _cell_var(ld, p + i)
    end
    t = mk_expr(T, kids)
    # TRANSITIONAL (L1c; user, 2026-10-15: approved): the export memo — REMOVED when the term-level
    # cycle detectors work on the cells (L1d: do_unify, compare, the occurs check; L1f: copy_term).
    ld.gterms[p] = t
    # TRANSITIONAL (L1d; user, 2026-10-15): the reverse map — a store of this export is ITS word
    # (`_compound_word!`). It follows the memo: an entry is live only while `gterms[p] === t`
    # (`_export_pos`), so the truncation (`Undo!`'s hot path) deletes nothing — `delete!` on an
    # IdDict allocates (AllocCheck: `jl_eqtable_pop`) — and the dead entries are purged here, on
    # the cold path, once they outnumber the live memo
    ld.gterm_of[t] = p
    length(ld.gterm_of) > 2 * ld.ngterm + 64 && _purge_gterm_of!(ld)
    n = ld.ngterm + 1
    n > length(ld.gterm_pos) ? push!(ld.gterm_pos, p) : (ld.gterm_pos[n] = p)
    ld.ngterm = n
    Threads.atomic_add!(_COLD_EXPORT_TERMS, 1)
    return t
end

# ORIGINAL: the reverse map's lookup (L1c; TRANSITIONAL with the memo): the position whose live
# export `t` is — `gterms[p] === t` — or 0 for any other term (a stale export: its position was
# truncated, or holds another compound now).
"The global position of the compound whose LIVE export is `t`, or 0."
@inline function _export_pos(ld::PL_local_data{T}, t::T)::Int where {T}
    p = get(ld.gterm_of, t, 0)
    return (p != 0 && p <= ld.gTop && ld.gterms[p] === t) ? p : 0
end

# ORIGINAL: the reverse map rebuilt from the live memo entries (L1c; TRANSITIONAL with the memo) —
# called from the cold export when the dead entries outnumber the live ones, never from `Undo!`.
"Drop the reverse map's dead entries: rebuild it from the live memo."
@noinline function _purge_gterm_of!(ld::PL_local_data{T})::Nothing where {T}
    empty!(ld.gterm_of)
    for i in 1:(ld.ngterm)
        p = ld.gterm_pos[i]
        ld.gterm_of[ld.gterms[p]::T] = p
    end
    return nothing
end

# ORIGINAL: the export memo follows the global stack down (L1c), as the value table does: every
# entry at a position above `gTop` goes. TRANSITIONAL, with the memo.
"Drop the exports of the compounds above `gTop` (in place: `Undo!` allocates nothing)."
function _truncate_gterms!(ld::PL_local_data{T})::Nothing where {T}
    n = ld.ngterm
    n == 0 && return nothing
    top = ld.gTop
    j = 0
    for i in 1:n                                    # positions in no order: compacted in place
        p = ld.gterm_pos[i]
        if p <= top
            j += 1
            ld.gterm_pos[j] = p
        else
            ld.gterms[p] = nothing                  # (its reverse-map entry: stale, see `_export_pos`)
        end
    end
    ld.ngterm = j
    return nothing
end

# ORIGINAL — THE COLD IMPORT (L1c): a compound TERM copied onto the global stack, for a writer that
# does not work on words yet (a built-in's result, a query's argument, a keyed variable's binding
# stored in a cell) — so neither the value table nor a `SLOT_VALUE` slot holds a compound. COUNTED in
# `cold_imports`. ITERATIVE (a long list nests in its last argument): each compound's cells laid out,
# then its arguments written — an atom its word, a live cell variable a reference to its cell (its
# identity kept: upstream's `makeRefG`), a nested compound its own copy, anything else (a number, a
# string, a keyed variable) a value-table word.
"Copy the compound term `t` onto the global stack; its compound word (the cold import, counted)."
function _compound_word!(ld::PL_local_data{T}, t::T)::word where {T}
    # the export of a compound still on the stack: ITS word, no copy — upstream shares the pointer
    # (`*ARGP = *k`, `Trail(t1, w2)`); a copy made the error term of the occurs check reference
    # cells the check's Undo had freed (test_catch_swipl.jl t24: `occurs_check(_, g(_))`, 2026-10-15)
    p = _export_pos(ld, t)
    p != 0 && return consPtr(p, TAG_COMPOUND | STG_GLOBAL)
    ld.cold_imports += 1
    todo = Tuple{T, Int}[]
    root = _import_layout!(ld, t, todo)
    while !isempty(todo)
        u, p = pop!(todo)
        off = _import_offset(u)
        for i in 1:(nchildren(u) - off)
            c = child(u, i + off)
            kc = kind(c)
            w = if kc === SYM
                _atom_word!(ld, c)
            elseif kc === EXPR
                _import_layout!(ld, c, todo)
            elseif kc === VAR
                r = _var_ref_word(ld, c)
                r != 0 ? r : _vword!(ld, c)
            else
                _vword!(ld, c)
            end
            ld.gstack[p + i] = w
        end
    end
    return root
end

# ORIGINAL: how many leading children of `u` the functor names: 1 for a symbol head, 0 for `$expr`.
"The children of compound term `u` that are not arguments: 1 (a symbol head) or 0 (`\$expr`)."
@inline _import_offset(u)::Int = (nchildren(u) >= 1 && kind(child(u, 1)) === SYM) ? 1 : 0

# ORIGINAL: the cells of one compound of an import, its arguments still to be written.
"Lay out compound term `u`'s cells and queue its arguments; its compound word."
function _import_layout!(
    ld::PL_local_data{T}, u::T, todo::Vector{Tuple{T, Int}}
)::word where {T}
    off = _import_offset(u)
    n = nchildren(u) - off
    name = off == 1 ? _atom_word!(ld, child(u, 1)) : ld.atom_dexpr
    p = _alloc_compound!(ld, lookupFunctorDef(ld.functors, name, n), n)
    push!(todo, (u, p))
    return consPtr(p, TAG_COMPOUND | STG_GLOBAL)
end

# ORIGINAL: the value a cell's word holds (L1b stage C2): unbound (0), an atom (C3), a reference —
# the variable of the cell it points at, which `deRef` follows on (L1c) — a compound on the stack,
# as a term through the cold export (L1c), or a value-table entry.
"The value word `w` of a bound cell names, or `nothing` for an unbound cell (the word 0)."
@inline function _cell_value(ld::PL_local_data{T}, w::word)::Union{Nothing, T} where {T}
    isVar(w) && return nothing
    isAtomW(w) && return _atom_value(ld, w)
    isRef(w) && return _cell_var(ld, unRef(w))
    _is_gcompound(w) && return _compound_term(ld, valPtr(w))
    return ld.vtable[valPtr(w)]
end

# ORIGINAL: the value table follows the global stack down (L1b stage C2): every entry whose box lies
# above `gTop` is gone with it.
"Drop the value-table entries whose boxes lie above `gTop`."
@inline function _truncate_vtable!(ld::PL_local_data)::Nothing
    while !isempty(ld.vbox) && ld.vbox[end] > ld.gTop
        pop!(ld.vbox)
        pop!(ld.vtable)
    end
    return nothing
end

# ORIGINAL: what a variable is bound to, for the few readers that look a binding up by key.
"The value variable `key` is bound to, or `nothing` (unbound): its cell, or the store."
@inline function _binding(ld::PL_local_data{T}, key::UInt64)::Union{Nothing, T} where {T}
    p = _cell_pos(ld, key)
    return p != 0 ? _cell_value(ld, ld.gstack[p]) : get(ld.bindings, key, nothing)
end

# ORIGINAL: bind without a trail entry — the callers that restore the binding themselves.
"Bind variable `key` to `v` WITHOUT trailing it: its cell, or the store."
function _set_binding!(ld::PL_local_data{T}, key::UInt64, v::T)::Nothing where {T}
    p = _cell_pos(ld, key)
    if p != 0
        ld.gstack[p] = _word_of!(ld, v)  # *p = v
    else
        ld.bindings[key] = v
    end
    return nothing
end

# ── the trail's entries (L1b stage D; src/pl-global.jl) ─────────────────────────────────────────
# ORIGINAL: the address entry's stack codes: upstream's address says which stack itself.
"Trail stack code: a cell of the global stack."
const TRAIL_GLOBAL = 0
"Trail stack code: a KEYED variable — entry `pos` of `trail_keys` (until the stamp falls)."
const TRAIL_KEYED = 2

# ORIGINAL: an address entry, `(pos << 3) | (stack << 1) | TAG_TRAILADDR`.
"The address entry naming position `p` of stack code `stack`."
_trail_addr(p::Int, stack::Int)::word =
    (UInt64(p) << 3) | (UInt64(stack) << 1) | TAG_TRAILADDR
"The stack code of address entry `e`."
_trail_stack(e::word)::Int = Int((e >> 1) & 0x3)
"The position address entry `e` names."
_trail_pos(e::word)::Int = Int(e >> 3)

# ORIGINAL: the variable an address entry names, for the readers that build it (unifiable/3, the
# occurs check, records, the writer): a cell's key from the position it names, a keyed one's from
# `trail_keys`.
"The key of the variable address entry `e` names."
function _trail_key(ld::PL_local_data, e::word)::UInt64
    _trail_stack(e) == TRAIL_KEYED && return ld.trail_keys[_trail_pos(e)]
    return _cell_key(ld, _trail_pos(e))
end

# ORIGINAL: `setVar(*tt->address)` for an address entry: a cell to 0, a keyed variable out of the
# store (and its key off `trail_keys`, which the entries above it have left).
"Reset the variable address entry `e` names, as the newest entry popped."
function _untrail!(ld::PL_local_data, e::word)::Nothing
    if _trail_stack(e) == TRAIL_KEYED
        @assert _trail_pos(e) == length(ld.trail_keys) "trail_keys out of step with the trail"
        delete!(ld.bindings, pop!(ld.trail_keys))
    else
        ld.gstack[_trail_pos(e)] = word(0)  # setVar(*p)
    end
    return nothing
end

# ORIGINAL: drop the entries above `n` WITHOUT undoing them (a frozen ball's bindings,
# `copy_exception!`), `trail_keys` kept in step.
"Truncate the trail to `n` entries, leaving their bindings in place."
function _trail_truncate!(ld::PL_local_data, n::Int)::Nothing
    while length(ld.trail) > n
        e = pop!(ld.trail)
        !isTrailVal(e) && _trail_stack(e) == TRAIL_KEYED && pop!(ld.trail_keys)
    end
    return nothing
end

# ── the local stack's slots: three accessors (L1b) ───────────────────────────────────────────────
# Every read and write of a slot goes through one of these, so that L1b's switch of the slots to
# WORDS (pl-data.h) changes three functions, not the 400 sites that call them (the L1 plan, §5 —
# docs/research/logickernel-step-memos/L1_plan/l1_plan.md in the workspace). `i` is the slot's
# 1-based position on the local stack: term reference `t` is position `t + 1`.

# ORIGINAL: THE SLOT WORDS (L1b stage C5; the workspace's L1_plan/stageC_design.md). A slot holds one
# of four words: `makeRefG(p)`, a reference to the cell variable at global position `p` (every
# live cell variable, whether the VM made it or it arrived as a term); an atom
# word, when one arrives as a word (copied from a cell); a COMPOUND word, a compound on the global
# stack (L1c: built there by the VM, or a term copied there by the cold import); or `SLOT_VALUE`,
# whose value is the slot's OWN entry of `slot_values` — a value with no word form yet (a float, big
# integer, string or small integer until L1d; a keyed variable until the stamp falls), or a symbol
# that arrived as a term (converting it would cost a lookup per store). DIVERGES,
# transitional: the side entry is the slot's own, so a copy of a `SLOT_VALUE` word copies the value
# too (`_slot_copy!`) and no word names another slot's entry. The word 0 is a slot never written.
"The slot word whose value is the slot's own entry of `slot_values` (L1b stage C5)."
const SLOT_VALUE = TAG_COMPOUND | STG_LOCAL

# ORIGINAL: the slot read (L1b stage C5: built from the slot's word; allocation-free — a variable
# term is a struct with no box, and an atom's symbol is cached).
"The value slot `i` holds (the term reference `t` is slot `t + 1`)."
@inline function slotValue(ld::PL_local_data{T}, i::Int)::T where {T}
    w = ld.slots[i]
    w == SLOT_VALUE && return ld.slot_values[i]
    isRef(w) && return _cell_var(ld, unRef(w))
    _is_gcompound(w) && return _compound_term(ld, valPtr(w))   # the cold export (L1c)
    return _slot_atom(ld, w)
end

# ORIGINAL: the rest of `slotValue`, out of line: an atom word, or a slot never written.
"The symbol of the atom word `w` a slot holds; a slot never written (the word 0) is an error."
function _slot_atom(ld::PL_local_data{T}, w::word)::T where {T}
    isAtomW(w) && return _atom_value(ld, w)
    throw(_slot_word_error(w))
end

# ORIGINAL: the error of a slot word that is none of the three forms.
"The internal error of a slot holding `w`, none of the slot words (0: never written)."
@noinline _slot_word_error(w::word)::Exception = ErrorException(
    "slot word $(repr(w)): a slot read before it was written, or a word that is no slot word"
)

# ORIGINAL: a term's slot word (L1b stage C5): a LIVE cell variable is its reference, anything else
# the slot's own side entry. `_var_ref_word` is the one place that knows a cell from a keyed variable.
"Store the term `v` in slot `i` as its word."
@inline function _slot_store!(ld::PL_local_data{T}, i::Int, v::T)::Nothing where {T}
    if kind(v) === EXPR                                         # a copy on the stack (L1c)
        ld.slots[i] = _compound_word!(ld, v)
        return nothing
    elseif kind(v) === VAR
        r = _var_ref_word(ld, v)
        if r != 0
            ld.slots[i] = r
            return nothing
        end
    end
    ld.slot_values[i] = v
    ld.slots[i] = SLOT_VALUE
    return nothing
end

# ORIGINAL: a term stored in slot `i` as a VALUE (L1c): a compound stays a term in the slot's side
# entry (`SLOT_VALUE`) instead of being copied onto the global stack — for the exception's ball,
# which the kernel keeps as a value outside the stacks (decision 1: upstream's `freezeGlobal`), so
# the `Undo` of the unwinding cannot free its cells; anything else as `_slot_store!`.
"Store the term `v` in slot `i`, a compound as a value (`SLOT_VALUE`), not copied onto the stack."
@inline function _slot_store_value!(ld::PL_local_data{T}, i::Int, v::T)::Nothing where {T}
    if kind(v) === EXPR
        ld.slot_values[i] = v
        ld.slots[i] = SLOT_VALUE
        return nothing
    end
    return _slot_store!(ld, i, v)
end

# ORIGINAL: a slot's word into another slot (L1b stage C5) — upstream's `*to = *from` between frame
# cells — the side entry with it.
"Copy slot `from`'s word to slot `to` (and its side entry, for `SLOT_VALUE`)."
@inline function _slot_copy!(ld::PL_local_data, to::Int, from::Int)::Nothing
    w = ld.slots[from]
    w == SLOT_VALUE && (ld.slot_values[to] = ld.slot_values[from])
    ld.slots[to] = w
    return nothing
end

# ORIGINAL: a fresh cell variable referenced from slot `i` (L1b stage C5) — upstream's `setVar` of a
# new global cell and its `makeRefG` into the frame — with no term built.
"Allocate a fresh cell variable and store its reference in slot `i`; returns its position."
@inline function _slot_new_var!(ld::PL_local_data, i::Int)::Int
    p = allocGlobalCells!(ld, 1)
    ld.slots[i] = makeRefG(p)
    return p
end

# ORIGINAL: the ENGINE's slot write — its own value, variable identity kept (upstream `setHandle`).
"Store the engine's value `v` in slot `i`; returns `v`, as the assignment it replaces did."
@inline function setSlotValue!(ld::PL_local_data{T}, i::Int, v::T)::T where {T}
    _slot_store!(ld, i, v)
    return v
end

# ORIGINAL: the variables one put shares with the puts that pass the same map (L1b): a caller's
# variable key → the key of its fresh cell. One map is one record's worth of variables — a goal's
# arguments put slot by slot with one map share them as SWI's record of the goal would.
# It DIVERGES from SWI as a Julia-side convenience with no C counterpart: SWI shares variables
# between puts only through `term_t` handles (`PL_put_term`), or by putting one compound.
"""
    PutVarMap()

The variables shared by the puts that pass this map (`putSlotValue!`): each caller variable met
by any of them is ONE fresh variable of the engine. A map is good while its cells live — not across
backtracking below the puts.
"""
struct PutVarMap
    cells::Dict{UInt64, UInt64}
end
PutVarMap() = PutVarMap(Dict{UInt64, UInt64}())

# ORIGINAL: THE BOUNDARY — a Julia caller's value put into a slot, with SWI's semantics (user,
# 2026-10-14): the value is COPIED as a record is (`copyRecordToGlobal`) — bindings followed, every
# unbound variable, a caller's or one of this engine's, a fresh cell, one per variable per `vm` — so
# separate puts make separate variables, and sharing with a variable already in the engine goes
# through its handle (`PL_put_term`, `setSlotValue!`), as in SWI's C interface. The put never asks
# whether a variable is a live cell: no stamp site.
"""
    putSlotValue!(ld, i, v[, vm]) -> the value put

Put a CALLER's value `v` into slot `i`: a copy with fresh variables, shared with the other puts
that pass the same `vm` (`PutVarMap`); without `vm`, a put of its own. Variable identity is the
handle: read an answer through the slot, never through the caller's variable.
"""
function putSlotValue!(ld::PL_local_data{T}, i::Int, v::T, vm::PutVarMap)::T where {T}
    vars = Dict{UInt64, T}()
    for (k, c) in vm.cells
        vars[k] = mk_var(T, c)
    end
    c = copy_term(ld, v, cp_options(true), vars)
    for (k, w) in vars
        vm.cells[k] = var_key(w)
    end
    _slot_store!(ld, i, c)
    return kind(c) === EXPR ? slotValue(ld, i) : c  # the value stored (L1c: a compound's export)
end
putSlotValue!(ld::PL_local_data{T}, i::Int, v::T) where {T} =
    putSlotValue!(ld, i, v, PutVarMap())

# PORT: pl-data.h deRef
# DIVERGES: follows a cell variable's cell, and a keyed variable's entry in the store, where
# upstream follows reference cells.
"`t` with its variable bindings followed: an unbound variable, or a non-variable (pl-data.h)."
function deRef(ld::PL_local_data{T}, t::T)::T where {T}
    while kind(t) === VAR
        b = _binding(ld, var_key(t))           # its cell, or the store (one place knows which)
        b === nothing && return t
        t = b
    end
    return t
end

# PORT: pl-inline.h linkValI
# DIVERGES: the dereferenced term. Upstream returns a reference to an unbound variable's cell
# (`makeRefG(p)`) and the value otherwise; a keyed variable IS its own reference (decision 2).
"The value to store for the term `t` refers to: `t` dereferenced (pl-inline.h)."
function linkValI(ld::PL_local_data{T}, t::T)::T where {T}
    return deRef(ld, t)
end

# PORT: pl-inline.h linkValI as _slot_link!
# DIVERGES: from slot to slot on the WORDS (L1b stage C6a): a reference is followed through the
# cells it is bound to; an unbound cell gives its reference, an atom or a compound (L1c) its word,
# and anything else
# (a value-table word, a `SLOT_VALUE`) its value into `to`'s side entry — a keyed variable
# dereferenced first, as `linkValI` on terms does.
"Store in slot `to` what slot `from` refers to, dereferenced (pl-inline.h `*to = linkValI(from)`)."
function _slot_link!(ld::PL_local_data{T}, to::Int, from::Int)::Nothing where {T}
    w = ld.slots[from]
    if isRef(w)
        p = unRef(w)
        while true
            c = ld.gstack[p]
            if isVar(c)                         # unbound: a reference to its cell
                ld.slots[to] = makeRefG(p)
                return nothing
            elseif isRef(c)
                p = unRef(c)
            elseif isAtomW(c) || _is_gcompound(c)   # an atom or a compound: its word (L1c)
                ld.slots[to] = c
                return nothing
            else
                _slot_store!(ld, to, deRef(ld, ld.vtable[valPtr(c)]))
                return nothing
            end
        end
    elseif w == SLOT_VALUE                          # a value stays a value (L1c: the ball)
        _slot_store_value!(ld, to, deRef(ld, ld.slot_values[from]))
    else
        (isAtomW(w) || _is_gcompound(w)) || throw(_slot_word_error(w))
        ld.slots[to] = w
    end
    return nothing
end

# PORT: pl-inline.h linkValI as _cell_link!
# DIVERGES: from slot `i` into the global cell `p` on the WORDS (L1c), as `_slot_link!` into a slot:
# a reference followed through the cells; an unbound cell gives its reference (upstream's
# `makeRefG(k)`), an atom, a compound or a value-table word its word (`*ARGP = *k`: an entry shared,
# as upstream shares an indirect; the entry's box lies below every cell that can reach it); a slot's
# side value dereferenced, as its word.
"Store in global cell `p` what slot `i` refers to, dereferenced (`*ARGP = linkValI(k)`)."
function _cell_link!(ld::PL_local_data{T}, p::Int, i::Int)::Nothing where {T}
    w = ld.slots[i]
    if isRef(w)
        q = unRef(w)
        while true
            c = ld.gstack[q]
            if isVar(c)
                ld.gstack[p] = makeRefG(q)
                return nothing
            elseif isRef(c)
                q = unRef(c)
            else                                # an atom, a compound, a value: its word
                ld.gstack[p] = c                    # (a value-table word shared, as upstream
                return nothing                      #  copies an indirect's pointer)
            end
        end
    elseif w == SLOT_VALUE
        ld.gstack[p] = _word_of!(ld, deRef(ld, ld.slot_values[i]))
    else
        (isAtomW(w) || _is_gcompound(w)) || throw(_slot_word_error(w))
        ld.gstack[p] = w
    end
    return nothing
end

# PORT: pl-inline.h Trail
# DIVERGES: a cell variable is trailed as upstream trails a global cell — only below
# `LD->mark_bar`; a KEYED variable (src/pl-global.jl) has no age, and is always trailed, as
# upstream always trails a local-stack cell (`p >= lBase`). Positions are 1-based and `gTop` is the
# LAST cell in use (upstream's `gTop` points at the first free word), so upstream's `p < mark_bar`
# is `p <= mark_bar` here.
"Bind variable `key` to `v`, recording it on the trail where backtracking must undo it (pl-inline.h)."
function Trail!(ld::PL_local_data{T}, key::UInt64, v::T)::Nothing where {T}
    p = _cell_pos(ld, key)
    if p != 0
        # if ( p < LD->mark_bar ) (tTop++)->address = p
        p <= ld.mark_bar && push!(ld.trail, _trail_addr(p, TRAIL_GLOBAL))
        ld.gstack[p] = _word_of!(ld, v)  # *p = v
    else
        push!(ld.trail_keys, key)               # (tTop++)->address = p: a keyed variable's entry
        push!(ld.trail, _trail_addr(length(ld.trail_keys), TRAIL_KEYED))
        ld.bindings[key] = v                    # *p = v
    end
    return nothing
end

# PORT: pl-incl.h Mark
"A mark at the current heights of the trail and the global stack; sets `mark_bar` (pl-incl.h `Mark`)."
function Mark(ld::PL_local_data)::mark
    m = mark(length(ld.trail), ld.gTop, ld.mark_bar)
    ld.mark_bar != NO_MARK_BAR && (ld.mark_bar = ld.gTop)
    return m
end

# PORT: pl-incl.h f_hasSpace
# QUIRK, as upstream: the distance is signed and `esize` unsigned, so C converts a NEGATIVE distance
# (`here` above `top`) to a huge unsigned one, and the answer is `true`. Callers that can see
# `lTop > lMax` test that first (`ENSURE_LOCAL_SPACE`, vmi:142).
"Whether `nelem` elements of `esize` fit between `here` and `top` (pl-incl.h)."
function f_hasSpace(here::Int, top::Int, nelem::Int, esize::Int)::Bool
    return reinterpret(UInt, top - here) ÷ UInt(esize) >= UInt(nelem)
end

# PORT: pl-incl.h hasLocalSpace
# DIVERGES: `n` is in positions, where upstream's is in bytes.
"Whether `n` positions are free above `lTop` (pl-incl.h)."
hasLocalSpace(ld::PL_local_data, n::Int)::Bool = f_hasSpace(ld.lTop, ld.lMax, n, 1)

# PORT: pl-incl.h DiscardMark
# DIVERGES: no `frozen_bar` — the kernel's ball is a value (decision 1).
"Abandon mark `m` without undoing to it: `mark_bar` back to what `m` replaced (pl-incl.h `DiscardMark`)."
function DiscardMark(ld::PL_local_data, m::mark)::Nothing
    ld.mark_bar = m.saved_bar
    return nothing
end

# PORT: pl-incl.h NoMark
"A mark that must never be undone to (pl-incl.h `NoMark`): a built-in's foreign frame has one."
NoMark()::mark = mark(NOT_A_MARK, 0, 0)

# PORT: pl-incl.h isRealMark
"Whether `m` was taken by `Mark`, not made by `NoMark` (pl-incl.h)."
isRealMark(m::mark)::Bool = m.trailtop != NOT_A_MARK

# PORT: pl-incl.h Undo
# DIVERGES: since L1b stage D the body of upstream's `Undo` WITH O_DESTRUCTIVE_ASSIGNMENT, pl-wam.c's
# `__do_undo`: newest first, an address entry resets its cell (a keyed variable leaves the store), a
# value entry steps down to its address entry and restores the old value saved on the global stack
# (`*tt->address = trailVal(p)`) — nothing pushes one yet (setarg/3, attributed variables). NOT
# PORTED: `push_undo` and `reclaim_attvars` (no attributed variables), and `frozen_bar` (the
# kernel's ball is a value, decision 1): `gTop = m.globaltop` (upstream: `max(frozen_bar, …)`,
# L1e). Marks nest: undoing to a mark above the trail's or the global stack's top is a misuse,
# asserted; so is undoing to a `NoMark`, which upstream never does.
"Undo every binding made since mark `m`, and free the cells allocated since (pl-incl.h `Undo`)."
function Undo!(ld::PL_local_data, m::mark)::Nothing
    @assert isRealMark(m) "Undo! to a NoMark"
    @assert m.trailtop <= length(ld.trail) "Undo! to a mark above the trail: marks undone out of order"
    @assert m.globaltop <= ld.gTop "Undo! to a mark above the global stack: marks undone out of order"
    while length(ld.trail) > m.trailtop        # while(--tt >= mt)
        e = pop!(ld.trail)
        if !isTrailVal(e)
            _untrail!(ld, e)                    # setVar(*p)
        else
            a = pop!(ld.trail)                  # tt--
            ld.gstack[_trail_pos(a)] = ld.gstack[trailValP(e)]     # *tt->address = trailVal(p)
        end
    end
    ld.gTop = m.globaltop                       # gTop = (b).globaltop
    _truncate_vtable!(ld)                       # (the value table follows it: L1b stage C2)
    _truncate_gterms!(ld)                       # (and the export memo: L1c)
    return nothing
end
