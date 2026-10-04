# UPSTREAM: swipl-devel src/pl-ressymbol.c @ bae881a24a3f
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
# NOT PORTED, and why: `initReservedSymbols` itself — it registers the blob type and retypes atoms
# in the atom table at start-up, and the kernel has no atom table; what it decides remains, as
# `RESERVED_SYMBOL_RANK` below and the reserved set above. The `--traditional` mode (`[]` is then the
# text atom `'[]'`) — the kernel is SWI-7; `_PL_atoms` (the foreign interface's table of special
# atoms); `blob_write_reserved_symbol` (it comes with the writer).

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

# PORT: pl-ressymbol.c ATOM_nil
# DIVERGES: upstream's `ATOM_nil` is the handle of `[]` in the atom table, and `argKey` keys `H_NIL`
# with it; the kernel has no atom table, so `[]`'s index key is a fixed atom word of its own —
# distinct from the key of the text atom `'[]'` (`MK_ATOM(sym_hash)`) but by chance, as any two keys.
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
#   * head code (src/pl-comp.jl `compileArgument!`): `H_FUNCTOR` with the word `expr_functor(n)`;
#   * index: a WILDCARD — `argKey` and `indexOfWord` give 0 — because unification goes child by
#     child (src/pl-prims.jl `_unify_functor`): `(X a)` unifies with `f(a)`, whose functor is `f/1`.
"The NAME of the `\$expr/n` functor (Q2), as `_functor_word` takes a name."
const ATOM_expr = MK_ATOM(UInt64(0x0024_4558_5052))          # "$EXPR", within the atom-number bits

"""
The functor word of `\$expr/n` (Q2): an `isFunctor` word, marked with `EXPR_FUNCTOR_MASK` — the
bit of upstream's `FIRST_MASK`, which no `name/arity` word has (src/pl-incl.jl, the word layout).
"""
expr_functor(n::Int)::word = _functor_word(UInt64(ATOM_expr), n) | EXPR_FUNCTOR_MASK

"True when `w` is the functor word of a `\$expr/n` (Q2)."
isExprFunctor(w::word)::Bool = isFunctor(w) && (w & EXPR_FUNCTOR_MASK) != 0
