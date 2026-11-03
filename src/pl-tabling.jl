# UPSTREAM: swipl-devel src/pl-tabling.c @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  2017-2025, VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# allow-new-artifact: a 1:1 port of swipl-devel src/pl-tabling.c (the upstream file was read at the pin; capability search in evidence/TAB1MIN/handoff.md)
#
# TABLING (pl-tabling.c): what boot/tabling.pl needs while it LOADS, and nothing of the tabled evaluation. The load-time
# path of a `:- table` directive (the expansion `wrappers//2`, tabling.pl:1273-1334) asks for the reserved symbol `trienode`
# (`'$tbl_trienode'/1`), the `tabled` attributes of a predicate (`def->tabling`, pl-tabling.c:10162-10393) and the wrapper
# (`'$c_wrap_predicate'/5`, src/pl-wrap.jl). This file holds, in the order of pl-tabling.c:
#   `'$tbl_trienode'/1` and `'$tbl_is_trienode'/1` (pl-tabling.c:6253-6277).
# The registration table (`PL_predicates_from_tabling`) lists the entries that exist; the other `$tbl_*` predicates, the tries,
# the worklists, the answer tables and `start_tabling/3` are TAB1 (NOT STARTED); the `tabled` attribute bits are TAB1-min step T2.

# ORIGINAL (TAB1MIN): pl-atom.ih `ATOM_trienode` (generated from src/ATOMS): the reserved atom `trienode` (src/pl-ressymbol.jl retypes it).
"The atom word of the reserved symbol `trienode` (pl-atom.ih `ATOM_trienode`): the same in every database."
const ATOM_trienode = builtin_atom("trienode")

# PORT: pl-tabling.c tbl_trienode as pl_tbl_trienode1_va
# (PRED_IMPL("$tbl_trienode", 1, tbl_trienode, 0))
# DIVERGES: the reserved symbol is built with `mk_reserved_symbol` (the term layer of the kernel) where upstream passes
# the atom `ATOM_trienode`; the unification is `PL_unify_atom` either way.
"`'\$tbl_trienode'(-X)`: `X` is the reserved node value for non-moded arguments (pl-tabling.c)."
function pl_tbl_trienode1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0

    return PL_unify_atom(ld, A1, mk_reserved_symbol(T, :trienode)) ? FTRUE : FFALSE
end

# PORT: pl-tabling.c tbl_is_trienode as pl_tbl_is_trienode1_va
# (PRED_IMPL("$tbl_is_trienode", 1, tbl_is_trienode, 0))
# DIVERGES: `(kind, word)` is the dereferenced location's (`_deref_loc`); upstream compares `*p == ATOM_trienode`.
"`'\$tbl_is_trienode'(@X)`: `X` is the reserved trie node (pl-tabling.c)."
function pl_tbl_is_trienode1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    k, w, _ = _deref_loc(ld, -(A1 + 1))

    return (k == DU_WORD && w == ATOM_trienode) ? FTRUE : FFALSE
end

# PORT: pl-tabling.c BeginPredDefs as PL_predicates_from_tabling
# DIVERGES: the ported entries, in upstream's order (upstream's table has the other `$tbl_*` predicates; `$tbl_trienode`
# and `$tbl_is_trienode` sit between `$tbl_destroy_table/1` and `$tbl_delay_list/1`).
"pl-tabling.c's registration table (`BeginPredDefs(tabling)`): the ported entries."
const PL_predicates_from_tabling = (
    PL_extension("\$tbl_trienode", 1, pl_tbl_trienode1_va, PL_FA_VARARGS),
    PL_extension("\$tbl_is_trienode", 1, pl_tbl_is_trienode1_va, PL_FA_VARARGS)
)
