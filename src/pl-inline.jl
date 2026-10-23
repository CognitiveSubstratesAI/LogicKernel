# UPSTREAM: swipl-devel src/pl-inline.h @ 8e1bc1110be4
# UPSTREAM: swipl-devel src/pl-incl.h @ 8e1bc1110be4
# UPSTREAM: swipl-devel src/pl-data.h @ 8e1bc1110be4
# UPSTREAM: swipl-devel src/pl-gvar.c @ 8e1bc1110be4
# CLASS: code
# COPYRIGHT: Copyright (c)  2008-2024, University of Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# SWI-Prolog's inline helpers the clause store uses: the bit scan behind bucket counts, the
# cleaning of hashed index keys, clause visibility in a generation, and the database generation —
# and the binding primitives the unifier (src/pl-prims.jl) is built on: the trail's entries, `Mark`
# and `Undo` (pl-incl.h macros) and `deRef` (a pl-data.h macro). They take the local data
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

# ORIGINAL: a value table's box (L1b stage C2) holds the word of its own entry, whose box is here —
# so a position a box occupies holds no variable (a cell's word names an entry boxed elsewhere, or
# is 0).
"Whether position `p` of the global stack is a value-table box."
@inline function _is_box(ld::PL_local_data, p::Int)::Bool
    w = ld.gstack[p]
    tagex(w) == (TAG_COMPOUND | STG_RESERVED) || return false
    i = valPtr(w)
    return i <= length(ld.vbox) && ld.vbox[i] == p
end

# ORIGINAL: a value-table word (`_vword!`): `TAG_COMPOUND|STG_RESERVED`, the entry's index its payload.
"Whether `w` is a value-table word (upstream: an indirect's word)."
@inline _is_vword(w::word)::Bool = tagex(w) == (TAG_COMPOUND | STG_RESERVED)

# ORIGINAL: the value table (L1b stage C2; src/pl-global.jl): a value with no word form yet, held
# by entry, pinned by a box word on the global stack so `Undo!` truncates the table with `gTop`.
"The word of a new value-table entry holding `v`; its box is the next word of the global stack."
@inline function _vword!(ld::PL_local_data{T}, v::T)::word where {T}
    p = ld.gTop + 1
    p > length(ld.gstack) && _growGlobalStack!(ld, p)
    push!(ld.vtable, v)
    push!(ld.vbox, p)
    w = consPtr(length(ld.vtable), TAG_COMPOUND | STG_RESERVED)
    ld.gstack[p] = w                  # the box: the entry's own word (`_is_box` tells it apart)
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

# ── tagged small integers (L1d step 4; the workspace's L1_plan/stageL1d_design.md §3b) ────────────
# PORT: pl-data.h consInt as _tagged_int_word
# (`TAG_INTEGER|STG_INLINE`, for the cells: the word of an integer in the tagged range)
# DIVERGES: an integer in the TAGGED range (`PLMINTAGGEDINT..PLMAXTAGGEDINT`, pl-incl.h) is its own
# word, IN the cell, as upstream's — no value-table entry; a bigger integer, a rational, a float or a
# string stays a value-table word (upstream's indirects, `STG_GLOBAL`). Only for a term type that
# can hold an `Int64` (`_holds_payload`, a compile-time constant): the word reads back as
# `mk_gnd(T, valInt(w))` — an `Int64` payload whatever integer type the term was made with (Prolog
# sees one integer type; representation only: an `Int32` payload in range reads back as `Int64`).
"The tagged-integer word of `v` when it is an integer in the tagged range (and `T` holds `Int64`), else 0."
@inline function _tagged_int_word(::Type{T}, v::T)::word where {T}
    _holds_payload(T, Int64) || return word(0)
    (number_kind(v) === NUM_INTEGER && integer_is_int64(v)) || return word(0)
    i = int64_value(v)
    return PLMINTAGGEDINT <= i <= PLMAXTAGGEDINT ? consInt(i) : word(0)
end

# ORIGINAL (L1d step 4): whether term type `T` can key a small integer by its WORD (`indexOfWord`'s
# `TAG_INTEGER: break`). A key must follow the term type's equality (CLAUDE.md): the word keys an
# integer by its value alone, which is right only when `T` keys integers at all and keys them APART
# from floats (a type whose `gnd_equal` made `1` and `1.0` one value would key them alike, and the
# word would split them into two buckets — a dropped answer). Both shipped term types qualify (SWI's
# identity: `1 \== 1.0`); a type that does not keeps its own keys (`_value_index_key`). Computed once
# per engine (`int_word_keys`).
"Whether term type `T` keys a small integer by its tagged word (see above)."
function _int_word_keys(::Type{T})::Bool where {T}
    _holds_payload(T, Int64) || return false
    k0 = gnd_key(mk_gnd(T, Int64(0)))
    k0 === nothing && return false
    _holds_payload(T, Float64) || return true
    return k0 != gnd_key(mk_gnd(T, 0.0))
end

# ORIGINAL: a GROUNDED value's word (L1d step 4): a small integer tagged, anything else a value-table
# entry (`_vword!`).
"The word of the grounded value `v`: a tagged integer, or a new value-table entry."
@inline function _gnd_word!(ld::PL_local_data{T}, v::T)::word where {T}
    w = _tagged_int_word(T, v)
    return w != 0 ? w : _vword!(ld, v)
end

# ORIGINAL: the VALUE a `DU_VALUE` word stands for (L1d step 4): a tagged integer's term (made: an
# `Int64` payload), or a value-table entry (stored). The readers that can decide on the word itself
# (unification, compare, the index, arithmetic, the VM's constants) never ask.
"The value term of `w`: a tagged integer (`mk_gnd(T, valInt(w))`), a value-table entry, or a slot's side value (a side word, f3-1)."
@inline function _value_term(ld::PL_local_data{T}, w::word)::T where {T}
    isTaggedIntW(w) && return mk_gnd(T, valInt(w))
    return _indirect_value(ld, w)
end

# ORIGINAL: a value's word on the global stack (L1b C3): an atom its own word, a compound a copy on
# the stack (L1c: `_compound_word!`, the cold import), a small integer its tagged word (L1d step 4:
# `consInt`), anything else a value-table entry (`_vword!`), a variable a fresh cell's reference
# (`_var_word!`: one write, its own variables — f3-2, audit D-0111, f3's Q3).
"The word that holds `v` in a cell."
@inline function _word_of!(ld::PL_local_data{T}, v::T)::word where {T}
    k = kind(v)
    k === SYM && return _atom_word!(ld, v)
    k === EXPR && return _compound_word!(ld, v)
    k === VAR && return _var_word!(ld, v)
    return _gnd_word!(ld, v)
end

# ORIGINAL (f3-2; audit D-0111, f3's Q3): `_word_of!`'s variable, a WRITE OF ITS OWN — ONE FRESH
# CELL, whose reference is the word (a term has no bindings since f3). The put semantics settled
# 2026-10-14 (`putSlotValue!`): separate writes are separate variables, and sharing with a variable
# already in the engine goes through its term reference, as in SWI's C interface. Until f3-2 two
# writes of one variable term shared a cell. The fresh cell is counted in `cold_imports`.
"The word a write of its own stores for the variable term `v`: a fresh cell's reference."
@noinline function _var_word!(ld::PL_local_data{T}, v::T)::word where {T}
    ld.cold_imports += 1                            # one fresh cell per variable per write
    return makeRefG(allocGlobalCells!(ld, 1))
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

# ORIGINAL — THE COLD IMPORT (L1c): a compound TERM copied onto the global stack, for a writer that
# does not work on words yet (a built-in's result, a query's argument) — so neither the value table
# nor a `SLOT_VALUE` slot holds a compound. COUNTED in `cold_imports`. ITERATIVE (a long list nests
# in its last argument): each compound's cells laid out, then its arguments written — an atom its
# word, a nested compound its own copy, a number or a string its word (a tagged integer, or a
# value-table word), a VARIABLE (f3-2, audit D-0111, f3's Q3) ONE FRESH CELL per variable per import
# — a write-local map, as a put's (`PutVarMap`), so the variable's occurrences in this term share the
# cell and a separate write of the same variable term is a separate variable (`_var_word!`). A term
# has no bindings since f3: nothing is followed, and no term names a compound on the stack.
"Copy the compound term `t` onto the global stack; its compound word (the cold import, counted)."
function _compound_word!(ld::PL_local_data{T}, t::T)::word where {T}
    ld.cold_imports += 1
    todo = Tuple{T, Int}[]
    root = _import_layout!(ld, t, todo)
    vm = nothing                                    # (f3-2: this write's variables, Q3)
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
            elseif kc === VAR                       # one fresh cell per variable per write (Q3)
                m = vm === nothing ? PutVarMap() : vm
                vm = m
                _write_var_word!(ld, m, var_key(c))
            else
                _gnd_word!(ld, c)                   # a small integer tagged (L1d step 4)
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

# ── the trail's entries (L1b stage D; src/pl-global.jl) ─────────────────────────────────────────
# ORIGINAL: the address entry's stack codes: upstream's address says which stack itself.
"Trail stack code: a cell of the global stack."
const TRAIL_GLOBAL = 0

# ORIGINAL: an address entry, `(pos << 3) | (stack << 1) | TAG_TRAILADDR`.
"The address entry naming position `p` of stack code `stack`."
_trail_addr(p::Int, stack::Int)::word =
    (UInt64(p) << 3) | (UInt64(stack) << 1) | TAG_TRAILADDR
"The stack code of address entry `e`."
_trail_stack(e::word)::Int = Int((e >> 1) & 0x3)
"The position address entry `e` names."
_trail_pos(e::word)::Int = Int(e >> 3)

# ORIGINAL: `setVar(*tt->address)` for an address entry: its cell to 0.
"Reset the variable address entry `e` names, as the newest entry popped."
function _untrail!(ld::PL_local_data, e::word)::Nothing
    ld.gstack[_trail_pos(e)] = word(0)  # setVar(*p)
    return nothing
end

# ORIGINAL: drop the entries above `n` WITHOUT undoing them (a frozen ball's bindings,
# `copy_exception!`).
"Truncate the trail to `n` entries, leaving their bindings in place."
function _trail_truncate!(ld::PL_local_data, n::Int)::Nothing
    length(ld.trail) > n && resize!(ld.trail, n)
    return nothing
end

# ── the local stack's slots: three accessors (L1b) ───────────────────────────────────────────────
# Every read and write of a slot goes through one of these, so that L1b's switch of the slots to
# WORDS (pl-data.h) changes three functions, not the 400 sites that call them (the L1 plan, §5 —
# docs/research/logickernel-step-memos/L1_plan/l1_plan.md in the workspace). `i` is the slot's
# 1-based position on the local stack: term reference `t` is position `t + 1`.

# ORIGINAL: THE SLOT WORDS (L1b stage C5; the workspace's L1_plan/stageC_design.md). A slot holds one
# of five words: `makeRefG(p)`, a reference to the cell variable at global position `p` (every
# live cell variable, whether the VM made it or it arrived as a term); an atom
# word, when one arrives as a word (copied from a cell); a COMPOUND word, a compound on the global
# stack (L1c: built there by the VM, or a term copied there by the cold import); a TAGGED INTEGER
# (L1d step 4: `consInt`, from a cell or a `*_SMALLINT` operand); or `SLOT_VALUE`,
# whose value is the slot's OWN entry of `slot_values` — since f3 only an indirect (a float, a big
# integer, a string) in a slot older than the innermost foreign frame (`_slot_store!`, audit D-0024).
# DIVERGES: the side entry is the slot's own, so a copy of a `SLOT_VALUE` word copies the value too
# (`_slot_copy!`) and no word names another slot's entry. The word 0 is a slot never written. Since
# f3-1 (audit D-0110, f3's Q1 (b)) the side entry is READ as a value: `_deref_loc` hands it out as its
# SIDE WORD (`_side_word`, below), `DU_VALUE`.
"The slot word whose value is the slot's own entry of `slot_values` (L1b stage C5)."
const SLOT_VALUE = TAG_COMPOUND | STG_LOCAL

# ORIGINAL (f3-1; audit D-0110, f3's Q1 (b)): the SIDE WORD — a slot's grounded side value read as a
# VALUE word (`DU_VALUE`, `_deref_loc`): `SLOT_VALUE`'s tag with the slot's index as its payload
# (`SLOT_VALUE` itself, payload 0, is only ever the slot's own word). A value reader reads it as it reads a value-table word, through `_indirect_value` (or
# `_value_term`). It is a READ-ONLY word, never stored: it names the slot's own entry, which a
# later write of the slot replaces — so a writer stores its value's own word instead
# (`_value_word!` into a cell: a fresh value-table entry, as `_word_of!` made one on the term path
# before f3-1), and a slot takes the value as `_slot_store!` stores it (`_slot_link_loc!`). The
# side value itself is D-0024's (`_slot_store!`): it makes upstream's undefined read defined.
"The side word of slot `i`: its side value (`slot_values[i]`) read as a value (f3-1)."
@inline _side_word(i::Int)::word = consPtr(i, SLOT_VALUE)

"Whether `w` is a side word (`_side_word`): a slot's grounded side value read as a value."
@inline _is_side_word(w::word)::Bool = tagex(w) == SLOT_VALUE

"The stored value an indirect's word names: a value-table entry, or a slot's side value (a side word, f3-1)."
@inline function _indirect_value(ld::PL_local_data{T}, w::word)::T where {T}
    _is_side_word(w) && return ld.slot_values[valPtr(w)]
    return ld.vtable[valPtr(w)]
end

"The word a cell stores for the value word `w`: `w` itself — a side word its value's own word (f3-1)."
@inline _value_word!(ld::PL_local_data, w::word)::word =
    _is_side_word(w) ? _side_value_word!(ld, w) : w

"The word of the side value a side word names: a new value-table entry holding it (`_gnd_word!`), as `_word_of!` makes one."
@noinline function _side_value_word!(ld::PL_local_data{T}, w::word)::word where {T}
    return _gnd_word!(ld, ld.slot_values[valPtr(w)])
end

# ORIGINAL: the error of a slot word that is none of the slot words (`_deref_loc`).
"The internal error of a slot holding `w`, none of the slot words (0: never written)."
@noinline _slot_word_error(w::word)::Exception = ErrorException(
    "slot word $(repr(w)): a slot read before it was written, or a word that is no slot word"
)

# ORIGINAL (L1e e1; the workspace's L1_plan/stageL1e_design.md §1): whether slot `i` is OLDER than the
# innermost foreign frame — a term reference made before `PL_open_foreign_frame`. A value-table entry made
# now is dropped by that frame's rewind (`_truncate_vtable!` with `gTop`) while the slot lives on, so such a
# slot keeps its own side value (`SLOT_VALUE`): its read stays defined, where upstream's is not (PL_put_float
# writes the reference untrailed, and the float's cells are freed by the rewind). The VM's own frames need
# no test: no VM writer overwrites a slot still live below a choice point (test_slot_words.jl, the review of
# 2026-10-15), as upstream's compiler guarantees for its frames. Pinned: test_slot_indirects.jl's probe.
"Whether slot `i` lies below the innermost foreign frame (it can outlive a value-table entry made now)."
@inline function _slot_older_than_fli(ld::PL_local_data, i::Int)::Bool
    c = ld.fli_context
    return c != 0 && i <= ld.fliframes[c].base
end

# ORIGINAL: a term's slot word (L1b stage C5): a compound its copy on the stack, an atom its word, a
# number its word, a variable a fresh cell's reference (`_slot_store_var!`: a write of its own,
# f3-2). Only a slot OLDER than the innermost foreign frame keeps a side value
# (`SLOT_VALUE`): an indirect (a float, a big integer, a string), whose word that frame's rewind
# would free while the slot lives on — the read stays defined (L1e e1, audit D-0024: upstream's is
# not). DECIDED (audit D-0110, f3's Q1 (b)): the indirect's side value STAYS — a divergence for
# safety (upstream: the reference dangles after the rewind, its read undefined), revisited after L1
# in the divergence review — and since f3-1 it is READ as a value (`_side_word`, `DU_VALUE`). A
# variable gets a fresh cell wherever the slot lies (f3-2, audit D-0111, f3's Q3), as
# `PL_put_variable` gives it one.
"Store the term `v` in slot `i` as its word."
@inline function _slot_store!(ld::PL_local_data{T}, i::Int, v::T)::Nothing where {T}
    k = kind(v)
    if k === EXPR                                               # a copy on the stack (L1c)
        ld.slots[i] = _compound_word!(ld, v)
        return nothing
    elseif k === VAR                                            # a fresh cell
        return _slot_store_var!(ld, i, v)
    elseif k === SYM                                            # its atom word (L1e e1)
        ld.slots[i] = _atom_word!(ld, v)
        return nothing
    elseif k === GND                                            # L1e e1: a tagged integer, or an
        w = _tagged_int_word(T, v)                              # indirect's word unless the slot
        if w == 0 && !_slot_older_than_fli(ld, i)               # outlives the entry (see below)
            w = _vword!(ld, v)
        end
        if w != 0
            ld.slots[i] = w
            return nothing
        end
    end
    ld.slot_values[i] = v                                       # older than the foreign frame (above)
    ld.slots[i] = SLOT_VALUE
    return nothing
end

# ORIGINAL (f3-2; audit D-0111, f3's Q3): `_slot_store!`'s variable, a WRITE OF ITS OWN (as
# `_var_word!`): ONE FRESH CELL referenced from the slot (`_slot_new_var!`, counted in
# `cold_imports`), wherever the slot lies, as `PL_put_variable` does. Separate writes are separate
# variables: sharing goes through a term reference (`PL_put_term`).
"Store the variable term `v` in slot `i`: a fresh cell's reference."
@noinline function _slot_store_var!(ld::PL_local_data{T}, i::Int, v::T)::Nothing where {T}
    ld.cold_imports += 1                            # one fresh cell per variable per write
    _slot_new_var!(ld, i)
    return nothing
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

# ORIGINAL: the ENGINE's slot write — its own value (upstream `setHandle`). A variable term is a
# write of its own since f3-2 (audit D-0111, f3's Q3: `_slot_store_var!`, a fresh cell): a
# variable's identity across writes goes through its term reference (`PL_put_term`), as SWI's.
"Store the engine's value `v` in slot `i`; returns `v`, as the assignment it replaces did."
@inline function setSlotValue!(ld::PL_local_data{T}, i::Int, v::T)::T where {T}
    _slot_store!(ld, i, v)
    return v
end

# ORIGINAL: the variables one put shares with the puts that pass the same map (L1b): a caller's
# variable key → the POSITION of its cell (f3b-1; the key of its fresh cell until then). One map is
# one record's worth of variables — a goal's arguments put slot by slot with one map share them as SWI's
# record of the goal would.
# It DIVERGES from SWI as a Julia-side convenience with no C counterpart: SWI shares variables
# between puts only through `term_t` handles (`PL_put_term`), or by putting one compound.
"""
    PutVarMap()

The variables shared by the puts that pass this map (`putSlotValue!`): each caller variable met
by any of them is ONE fresh variable of the engine — `cells[var_key(x)]` is its cell's position. A map
is good while its cells live — not across backtracking below the puts.
"""
struct PutVarMap
    cells::Dict{UInt64, Int}
end
PutVarMap() = PutVarMap(Dict{UInt64, Int}())

# ORIGINAL (f3-2; audit D-0111, f3's Q3): a writer's write-local variable map (`_compound_word!`,
# `import_cells!`) — the put's map (`PutVarMap`) for a write of a term: the unbound variable `key`'s
# cell in `vm`, a fresh one on its first sight (counted in `cold_imports`).
"The reference word of the cell that write-local map `vm` gives the unbound variable `key` (a fresh cell on first sight)."
function _write_var_word!(ld::PL_local_data, vm::PutVarMap, key::UInt64)::word
    p = get(vm.cells, key, 0)
    if p == 0
        p = allocGlobalCells!(ld, 1)
        ld.cold_imports += 1
        vm.cells[key] = p
    end
    return makeRefG(p)
end

# ORIGINAL: THE BOUNDARY — a Julia caller's value put into a slot, with SWI's semantics (user,
# 2026-10-14): the value is COPIED as a record is (`copyRecordToGlobal`) — every variable a fresh
# cell, one per variable per `vm` — so separate puts make separate variables, and sharing with a
# variable already in the engine goes through its handle (`PL_put_term`, `setSlotValue!`), as in
# SWI's C interface. Since f3b-1 (F1-Q4 (a), audit D-0042) the value
# is LAID OUT on the cells directly, no term walk (`copy_term`) and no export, in two passes: first a
# fresh cell for each new variable, in depth-first order of first occurrence — the order the term walk
# made them in until f3b-1, and the order swipl's reader makes a goal's variables in (the standard order
# of variables follows it); then each compound's cells at its first visit, depth-first, its variable
# arguments references to their cells (toward the lower cell, as pl-rec.c `copy_record` keeps them). A
# compound met again by identity (a subterm shared) is laid out once and referenced again
# (`copy_record`'s `PL_REC_CYCLE`). A value has no identity, so every compound is copied (a record
# copies every cell: nothing of the value is shared with the stacks).
"""
    putSlotValue!(ld, i, v[, vm])

Put a CALLER's value `v` into slot `i`: a copy with fresh variables, shared with the other puts
that pass the same `vm` (`PutVarMap`); without `vm`, a put of its own. Variable identity is the
handle: read the value — and an answer — through the slot (`export_cells`, `query_answers`), never
through the caller's variable. (Until f3b-1 it returned the value stored, read back through the cold
export.)
"""
function putSlotValue!(ld::PL_local_data{T}, i::Int, v::T, vm::PutVarMap)::Nothing where {T}
    k = kind(v)
    if k === EXPR
        ld.slots[i] = _put_compound!(ld, v, vm)
    elseif k === VAR                                # one fresh cell per variable per map
        key = var_key(v)
        p = get(vm.cells, key, 0)
        if p == 0
            p = allocGlobalCells!(ld, 1)
            vm.cells[key] = p
        end
        ld.slots[i] = makeRefG(p)
    else                                            # an atom or a number: its word (in a slot older
        _slot_store!(ld, i, v)                      # than the innermost foreign frame an indirect's
    end                                             # side value, D-0024 — as before f3b-1)
    return nothing
end
putSlotValue!(ld::PL_local_data{T}, i::Int, v::T) where {T} =
    putSlotValue!(ld, i, v, PutVarMap())

# ORIGINAL (f3b-1): `putSlotValue!`'s compound laid out on the cells — see there. ITERATIVE (a long list
# nests in its last argument): the work stack holds each compound being filled and its next argument, so
# the arguments are visited depth-first, left to right — the order a record's variables are numbered in
# (`compile_term_to_heap`); the variables' cells are made first, in that order (`_put_vars!`).
"Lay the compound `t` out on the global stack as `putSlotValue!` copies it; its compound word."
function _put_compound!(ld::PL_local_data{T}, t::T, vm::PutVarMap)::word where {T}
    _put_vars!(ld, t, vm)                           # the new variables' cells, in order
    done = IdDict{T, word}()                        # the compounds laid out: met again, referenced
    stack = Tuple{T, Int, Int}[]                    # (compound, its functor cell, its next argument)
    root = _put_layout!(ld, t, stack, done)
    while !isempty(stack)
        u, p, i = stack[end]
        off = _import_offset(u)
        if i > nchildren(u) - off
            pop!(stack)
            continue
        end
        stack[end] = (u, p, i + 1)
        c = child(u, i + off)
        kc = kind(c)
        if kc === EXPR
            w = get(done, c, word(0))
            ld.gstack[p + i] = w != 0 ? w : _put_layout!(ld, c, stack, done)
        elseif kc === VAR                           # its cell, made by `_put_vars!` (or an earlier put)
            ld.gstack[p + i] = makeRefG(vm.cells[var_key(c)])
        elseif kc === SYM
            ld.gstack[p + i] = _atom_word!(ld, c)
        else
            ld.gstack[p + i] = _gnd_word!(ld, c)    # a tagged integer, or a value-table word
        end
    end
    return root
end

# ORIGINAL (f3b-1): one compound of `_put_compound!`: its cells (the arguments unbound), recorded in
# `done` and pushed to be filled.
"Lay out the cells of compound `u` for `_put_compound!`; its compound word."
function _put_layout!(
    ld::PL_local_data{T}, u::T, stack::Vector{Tuple{T, Int, Int}}, done::IdDict{T, word}
)::word where {T}
    off = _import_offset(u)
    n = nchildren(u) - off
    name = off == 1 ? _atom_word!(ld, child(u, 1)) : ld.atom_dexpr
    p = _alloc_compound!(ld, lookupFunctorDef(ld.functors, name, n), n)
    w = consPtr(p, TAG_COMPOUND | STG_GLOBAL)
    done[u] = w
    push!(stack, (u, p, 1))
    return w
end

# ORIGINAL (f3b-1): `putSlotValue!`'s first pass — a fresh cell for each unbound variable of compound `t`
# that `vm` does not hold yet, in depth-first order of first occurrence (as `copy_term`'s walk made them
# until f3b-1); a compound met again by identity (a subterm shared) is not walked again.
"Give each new variable of the compound `t` a fresh cell in `vm`, depth-first."
function _put_vars!(ld::PL_local_data{T}, t::T, vm::PutVarMap)::Nothing where {T}
    seen = IdDict{T, Nothing}()
    seen[t] = nothing
    stack = Tuple{T, Int}[(t, 1)]                   # (compound, its next argument)
    while !isempty(stack)
        u, i = stack[end]
        off = _import_offset(u)
        if i > nchildren(u) - off
            pop!(stack)
            continue
        end
        stack[end] = (u, i + 1)
        c = child(u, i + off)
        kc = kind(c)
        if kc === VAR
            key = var_key(c)
            haskey(vm.cells, key) || (vm.cells[key] = allocGlobalCells!(ld, 1))
        elseif kc === EXPR && !haskey(seen, c)
            seen[c] = nothing
            push!(stack, (c, 1))
        end
    end
    return nothing
end

# PORT: pl-inline.h linkValI as _slot_link!
# DIVERGES: from slot to slot on the WORDS (L1b stage C6a): a reference is followed through the
# cells it is bound to; an unbound cell gives its reference, an atom, a compound (L1c) or a small
# integer its word, and an indirect (a value-table word, a `SLOT_VALUE`) its word, shared — or, into
# a slot older than the innermost foreign frame, its value into `to`'s side entry (`_slot_store!`,
# audit D-0024).
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
            elseif isAtomW(c) || _is_gcompound(c) || isTaggedIntW(c)   # an atom, a compound or a small integer: its word (L1c, L1d step 4)
                ld.slots[to] = c
                return nothing
            elseif !_slot_older_than_fli(ld, to)
                ld.slots[to] = c                    # an indirect's word, shared (L1e e1)
                return nothing
            else
                _slot_store!(ld, to, ld.vtable[valPtr(c)])   # into a slot the entry cannot outlive
                return nothing
            end
        end
    elseif w == SLOT_VALUE                          # a side value: an indirect (D-0024)
        _slot_store!(ld, to, ld.slot_values[from])
    elseif _is_vword(w)                             # a value-table word (L1e e1): as from a cell
        if !_slot_older_than_fli(ld, to)
            ld.slots[to] = w
        else
            _slot_store!(ld, to, ld.vtable[valPtr(w)])
        end
    else
        (isAtomW(w) || _is_gcompound(w) || isTaggedIntW(w)) || throw(_slot_word_error(w))
        ld.slots[to] = w
    end
    return nothing
end

# PORT: pl-inline.h linkValI as _cell_link!
# DIVERGES: from slot `i` into the global cell `p` on the WORDS (L1c), as `_slot_link!` into a slot:
# a reference followed through the cells; an unbound cell gives its reference (upstream's
# `makeRefG(k)`), an atom, a compound or a value-table word its word (`*ARGP = *k`: an entry shared,
# as upstream shares an indirect; the entry's box lies below every cell that can reach it); a slot's
# side value (an indirect, audit D-0024) as its value's own word.
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
        ld.gstack[p] = _word_of!(ld, ld.slot_values[i])
    else                                            # an atom, a compound, a small integer or (L1e
        (isAtomW(w) || _is_gcompound(w) || isTaggedIntW(w) || _is_vword(w)) ||   # e1) a value-table
            throw(_slot_word_error(w))                                           # word: shared
        ld.gstack[p] = w
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
"Abandon mark `m` without undoing to it: `mark_bar` back to what `m` replaced, not below the frozen bar (pl-incl.h `DiscardMark`)."
function DiscardMark(ld::PL_local_data, m::mark)::Nothing
    ld.mark_bar = max(ld.frozen_bar, m.saved_bar)   # (frozen_bar > saved_bar ? frozen_bar : saved_bar)
    return nothing
end

# PORT: pl-gvar.c freezeGlobal as freezeGlobal!
"Freeze the global stack below `gTop` (pl-gvar.c `freezeGlobal`): no undo frees it, every binding of it trailed."
function freezeGlobal!(ld::PL_local_data)::Nothing
    ld.frozen_bar = ld.mark_bar = ld.gTop          # LD->frozen_bar = LD->mark_bar = gTop
    return nothing
end

# ORIGINAL (e5; audit D-0029 option (b)): the frozen region released when the OUTERMOST query ends.
# DIVERGES: upstream keeps `frozen_bar` for the thread's life (pl-gvar.c `destroyGlobalVars`) and its
# garbage collector frees a frozen ball once nothing references it; the kernel has no collector until G1,
# so without this every throw would pin the global stack below its ball for the engine's life
# (evidence/A-0029 in the audit channel). When the outermost query has ended (`ld.query == 0`) with no
# exception pending, nothing the engine runs can reach the region: the bar is lowered to 0 and, after a
# CLOSE, `gTop` to the query's own mark `target` — but first every live term reference (the slots below
# `lTop`) and every open foreign frame's mark is checked to point at or below `target` (raises
# otherwise). GOES with G1 (the collector). REVISIT when nb_setval/b_setval are ported: upstream freezes
# for global variables too, and this reset would free a global variable's value.
"Release the frozen region after the outermost query ended, its mark `m` (`close`: lower `gTop` to `m.globaltop`)."
function _release_frozen!(ld::PL_local_data, m::mark, close::Bool)::Nothing
    target = m.globaltop
    (ld.frozen_bar == 0 || ld.query != 0 || ld.exception_term != 0) && return nothing
    if close && ld.gTop > target
        for i in 1:(ld.lTop)                        # live term references: none above `target`
            w = ld.slots[i]
            p = if isRef(w)
                unRef(w)
            elseif _is_gcompound(w)
                valPtr(w)
            elseif _is_vword(w)
                ld.vbox[valPtr(w)]
            else
                0
            end
            p > target && error(
                "_release_frozen!: slot $i references global position $p above the reset target $target"
            )
        end
        for f in 1:(ld.nfliframes)                  # open foreign frames: none above `target`
            g = ld.fliframes[f].mark.globaltop
            g > target && error(
                "_release_frozen!: foreign frame $f's mark $g lies above the reset target $target"
            )
        end
    end
    ld.frozen_bar = 0
    ld.mark_bar = m.saved_bar                       # what DiscardMark(m) restores with no frozen bar
    if close && ld.gTop > target
        ld.gTop = target                            # what Undo!'s max(frozen_bar, …) kept
        _truncate_vtable!(ld)
    end
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
# `__do_undo`: newest first, an address entry resets its cell, a value entry steps down to its address entry and restores the old value saved on the global stack
# (`*tt->address = trailVal(p)`) — nothing pushes one yet (setarg/3, attributed variables). NOT
# PORTED: `push_undo` and `reclaim_attvars` (no attributed variables). Since e5 `frozen_bar` is kept:
# `gTop = max(frozen_bar, m.globaltop)`. Marks nest: undoing to a mark above the trail's or the global stack's top is a misuse,
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
    ld.gTop = max(ld.frozen_bar, m.globaltop)   # gTop = (frozen_bar > globaltop ? frozen_bar : globaltop)
    _truncate_vtable!(ld)                       # (the value table follows it: L1b stage C2)
    return nothing
end
