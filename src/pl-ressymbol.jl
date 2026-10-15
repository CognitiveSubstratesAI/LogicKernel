# UPSTREAM: swipl-devel src/pl-ressymbol.c @ 8609e216cab9
# CLASS: code
# COPYRIGHT: Copyright (c)  2013-2024, VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# RESERVED SYMBOLS (SWI-7). A reserved symbol is an atom — the atom TAG — of the blob type
# `reserved_symbol`: unique like a text atom, but NOT text, so `atom/1` fails on it (`PL_is_atom` is
# `isTextAtom`, pl-fli.h) and it is a different symbol from the text atom of the same name. The type
# is ranked 0, "between normal blob and text" (pl-ressymbol.c:97), so in the standard order a
# reserved symbol sorts before every text atom; two reserved symbols compare by `strcmp`.
#
# In the kernel a reserved symbol is a `SYM` term for which the implementation's
# `is_reserved_symbol` holds (src/term_interface.jl — a flag, not a kind, user 2026-10-03); this file
# ports what upstream decides about them.
#
# THE RESERVED SET, as `initReservedSymbols` builds it in the default (non-traditional) mode:
#   `[]` (`ATOM_nil`)                  `reserved_symbols[]`; the kernel builds it with `mk_nil`.
#   `dict`, `trienode`, `no_value`,    retyped to `reserved_symbol` by the same function
#   `term_t_free` (`ATOM_dict`, …)     (pl-ressymbol.c:99-102). NOT PORTED: internal markers of
#                                      subsystems the kernel does not have yet — dicts, trie nodes,
#                                      the foreign interface's unbound and freed handles. Each comes
#                                      with its subsystem, built by `mk_reserved_symbol`.
# Since L1b stage A, `initReservedSymbols!` registers the blob type and retypes those atoms in the
# database's ATOM TABLE (src/pl-atom.jl), as upstream does at start-up; nothing reads the table's
# types yet (the terms still carry `is_reserved_symbol`) — stage C's words do.
# NOT PORTED, and why: the `--traditional` mode (`[]` is then the text atom `'[]'`) — the kernel is
# SWI-7; `_PL_atoms` (the foreign interface's table of special atoms); `blob_write_reserved_symbol`
# (it comes with the writer) and `compareReservedSymbol`'s place in the type (`PL_blob_t` carries
# no hooks).

# PORT: pl-ressymbol.c isReservedSymbol
"""
    isReservedSymbol(t) -> Bool

Whether `t` is a reserved symbol (pl-ressymbol.c): a `SYM` the term type marks reserved.
"""
isReservedSymbol(t)::Bool = kind(t) === SYM && is_reserved_symbol(t)

# PORT: pl-ressymbol.c compareReservedSymbol
"""
    compareReservedSymbol(a::Symbol, b::Symbol) -> Int

Two reserved symbols by their names, as `strcmp` (pl-ressymbol.c) — the `compare` function of the
`reserved_symbol` blob type, which `compareAtoms` calls when both atoms are reserved.
"""
compareReservedSymbol(a::Symbol, b::Symbol)::Int = a === b ? CMP_EQUAL : _sign(cmp(a, b))

# From `initReservedSymbols` (`reserved_symbol.rank = 0`; the function is not ported — see above).
"The rank of the `reserved_symbol` blob type: 0, \"between normal blob and text\" (pl-ressymbol.c)."
const RESERVED_SYMBOL_RANK = 0

# DIVERGES: pl-atom.c gives each text blob type `++GD->atoms.text_rank`; the kernel has one text type.
"The rank of a text atom: above 0, the rank of every text blob type (pl-atom.c)."
const TEXT_ATOM_RANK = 1

# DIVERGES: SWI has no grounded value outside its own types, so where one sorts is LogicKernel's
# decision (user, 2026-10-04: pinned, following SWI's nearest analogue). A grounded value of the
# kind query's NUM_OTHER sorts as a NON-TEXT BLOB does: pl-atom.c gives each non-text blob type
# `--GD->atoms.nontext_rank`, below 0, so it sorts after every number and string and before the
# reserved symbols (rank 0) and every text atom (above 0). swipl 10.1.16, probed: a stream, a clause
# reference and a mutex sort after "str" and before [] and ''. Every implementation's
# `atomic_compare` follows it; conformance and the compare differential pin it.
"The rank of an opaque grounded value (NUM_OTHER) among the atoms: a non-text blob type's, below 0."
const OTHER_BLOB_RANK = -1

# PORT: pl-ressymbol.c ATOM_nil
# DIVERGES: upstream's `ATOM_nil` is the handle of `[]` in the atom table, and `argKey` keys `H_NIL`
# with it; the kernel has no atom table, so `[]`'s index key is a fixed atom word of its own —
# distinct from every hashed key — the text atom `'[]'`'s among them — by construction (`_unreserved`,
# src/pl-index.jl; the divergence audit, S05).
"The index key of `[]`: what `argKey` reads from `H_NIL` and `indexOfWord` gives `[]`."
const ATOM_nil = MK_ATOM(UInt64(0x0052_4553_5652_4544))      # "RESERVED", within the atom-number bits

# ── `$expr/n` (Q2) ──────────────────────────────────────────────────────────────────────────────
# DIVERGES: SWI has no compound whose head is not an atom; the term interface has them — MeTTa's
# variable and compound heads, a grounded head, and `()` with no children. Q2 (user, 2026-10-03)
# gives each the functor `$expr/n`, `n` its number of children, whose arguments are ALL its
# children, head included. Its name is reserved, as upstream's reserved symbol `dict` names the
# functor of dicts (pl-dict.c `FUNCTOR_dict`): never the text atom `'$expr'`, so `'$expr'(X, a)`
# has another functor. It names a functor and nothing else — no term is the symbol `$expr`.
#   * standard order (src/pl-prims.jl `compare_functors`): by arity, then name — `$expr` before
#     every symbol, as a reserved symbol sorts before the text atoms and, by `strcmp`, before `[]`;
#   * head code (src/pl-comp.jl `compileArgument!`): `H_FUNCTOR` whose operand names NO literal —
#     literal index 0, `functor_operand(0, n, f)` — where a symbol head's names its literal (since V1 L2,
#     user 2026-10-04; Q2's marking bit is retired with it);
#   * index: a WILDCARD — `argKey` and `indexOfWord` give 0 — because unification goes child by
#     child (src/pl-prims.jl `_unify_functor`): `(X a)` unifies with `f(a)`, whose functor is `f/1`.

# PORT: pl-ressymbol.c reserved_symbol
# DIVERGES: flags and name only (`PL_blob_t`, src/SWI-Prolog.jl); `padding` is `sizeof(char)`, as
# upstream's (registration sets it for text types only: `blob_registration`).
"The blob type of a reserved symbol (pl-ressymbol.c): unique, NOT text."
const reserved_symbol = PL_blob_t(PL_BLOB_UNIQUE, "reserved_symbol")

# PORT: pl-ressymbol.c reserved_symbols
"The atoms that are reserved symbols in SWI-7 mode (pl-ressymbol.c): `[]` alone."
const reserved_symbols = ("nil",)                   # ATOM_nil: `[]`

# PORT: pl-ressymbol.c initReservedSymbols
# DIVERGES: on one database's atom table (`GD->atoms`); the atoms by their generated ids
# (`builtin_atom`); always SWI-7 (`!GD->options.traditional`).
"Register `reserved_symbol` and retype the reserved atoms (pl-ressymbol.c)."
function initReservedSymbols!(atoms::atoms_t)::Nothing
    r = PL_register_blob_type(atoms, reserved_symbol, builtin_atom("reserved_symbol"))
    r.padding = sizeof(UInt8)                           # the static type's `sizeof(char)`
    r.rank = 0                                          # sort between normal blob and text
    atoms.nontext_rank += 1
    for id in ("dict", "trienode", "no_value", "term_t_free")
        atomValue(atoms, builtin_atom(id)).type = reserved_symbol
    end
    for id in reserved_symbols
        atomValue(atoms, builtin_atom(id)).type = reserved_symbol
    end
    return nothing
end
