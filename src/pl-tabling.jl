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
#   then `clear_table_props!`, `tbl_reset_tabling_attributes!`, `get_predicate_table_props!`, `tbl_get_predicate_attribute`,
#   `get_size_or_inf`, `tbl_set_incremental_predicate`, `set_bool_attr`, `tbl_set_predicate_attribute` (pl-tabling.c).
# The registration table (`PL_predicates_from_tabling`) lists the entries that exist; the other `$tbl_*` predicates, the tries,
# the worklists, the answer tables and `start_tabling/3` are TAB1 (NOT STARTED). Since TAB1-min step T2 the file also holds the
# `tabled` attribute bits of a predicate (`def->tabling`, pl-tabling.c:10162-10393): clear, get, set, reset.

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

# PORT: pl-tabling.c clear_table_props
# DIVERGES: `lazy_queue` is not a field of `table_props` (see there); `(size_t)-1` is -1.
"Reset the tabling properties `p` of a predicate to the values of a new record (pl-tabling.c)."
function clear_table_props!(p::table_props)::Nothing
    p.flags = UInt32(0)
    p.abstract = -1
    p.subgoal_abstract = -1
    p.answer_abstract = -1
    p.max_answers = -1
    p.start_id = UInt32(0)
    return nothing
end

# PORT: pl-tabling.c tbl_reset_tabling_attributes
"Clear the tabling properties of `def`, if it has any: called by `resetProcedure!` (pl-tabling.c)."
function tbl_reset_tabling_attributes!(def::Definition)::Nothing
    p = def.tabling
    p === nothing || clear_table_props!(p)
    return nothing
end

# PORT: pl-tabling.c get_predicate_table_props
# DIVERGES: no `COMPARE_AND_SWAP_PTR` (no threads): the field is set once.
"The tabling properties of `def`, made and cleared if it has none (pl-tabling.c)."
function get_predicate_table_props!(def::Definition)::table_props
    p = def.tabling
    if p === nothing
        p = table_props()                       # clear_table_props(p)
        def.tabling = p
    end
    return p
end

# PORT: pl-tabling.c tbl_get_predicate_attribute
# DIVERGES: a Bool, and the closing `return -1` (a key the caller's `tbl_is_predicate_attribute` did not list) is `false`:
# every key it lists has its branch here. The size attributes answer `PL_unify_integer` of the `Int` (see `table_props`).
"Unify `value` with the tabling attribute `att` of `def`; false if `def` has no tabling properties (pl-tabling.c)."
function tbl_get_predicate_attribute(
    ld::PL_local_data{T}, def::Definition{T}, att::T, value::term_t
)::Bool where {T}
    p = def.tabling
    p === nothing && return false
    k = sym_key(att)
    if k == sym_key(mk_sym(T, :monotonic))
        return PL_unify_integer(ld, value, (p.flags & TP_MONOTONIC) != 0 ? 1 : 0)
    elseif k == sym_key(mk_sym(T, :incremental))
        return PL_unify_integer(ld, value, (p.flags & TP_INCREMENTAL) != 0 ? 1 : 0)
    elseif k == sym_key(mk_sym(T, :tshared))
        return PL_unify_integer(ld, value, (p.flags & TP_SHARED) != 0 ? 1 : 0)
    elseif k == sym_key(mk_sym(T, :opaque))
        return PL_unify_integer(ld, value, (p.flags & TP_OPAQUE) != 0 ? 1 : 0)
    elseif k == sym_key(mk_sym(T, :lazy))
        return PL_unify_integer(ld, value, (p.flags & TP_LAZY) != 0 ? 1 : 0)
    elseif k == sym_key(mk_sym(T, :tabled))
        return PL_unify_integer(ld, value, (p.flags & TP_TABLED) != 0 ? 1 : 0)
    elseif k == sym_key(mk_sym(T, :tabled_variant))
        return PL_unify_integer(ld, value, (p.flags & TP_VARIANT) != 0 ? 1 : 0)
    else
        if k == sym_key(mk_sym(T, :abstract))
            v0 = p.abstract
        elseif k == sym_key(mk_sym(T, :subgoal_abstract))
            v0 = p.subgoal_abstract
        elseif k == sym_key(mk_sym(T, :answer_abstract))
            v0 = p.answer_abstract
        elseif k == sym_key(mk_sym(T, :max_answers))
            v0 = p.max_answers
        else
            return false
        end
        v0 != -1 && return PL_unify_integer(ld, value, v0)
    end
    return false
end

# PORT: pl-tabling.c get_size_or_inf
# DIVERGES: returns the size (`typemax`'s role is -1: `infinite`), or `nothing` with the error raised.
"The size `t` holds: `infinite` is -1, else a non-negative integer (pl-tabling.c)."
function get_size_or_inf(ld::PL_local_data{T}, t::term_t)::Union{Nothing, Int} where {T}
    inf = PL_get_atom(ld, t)
    if inf !== nothing && sym_key(inf) == sym_key(mk_sym(T, :infinite))
        return -1
    end
    return PL_get_size_ex(ld, t)
end

# PORT: pl-tabling.c tbl_set_incremental_predicate
# DIVERGES: the database is an argument (a wrapped predicate keeps its wrapper: `freeCodesDefinition!` finds the closure there).
"Switch the incremental tabling of `def` on or off; a change resets its supervisor (pl-tabling.c)."
function tbl_set_incremental_predicate(
    gd::PL_global_data{T}, def::Definition{T}, val::Bool
)::Nothing where {T}
    p = get_predicate_table_props!(def)
    now = (p.flags & TP_INCREMENTAL) != 0

    if val != now
        if val
            p.flags |= TP_INCREMENTAL
        else
            p.flags &= ~TP_INCREMENTAL
        end
        freeCodesDefinition!(gd, def, true)
    end
    return nothing
end

# PORT: pl-tabling.c set_bool_attr
"Set or clear the tabling flag `flag` of `def` from the Boolean `value` holds (pl-tabling.c)."
function set_bool_attr(
    ld::PL_local_data{T}, def::Definition{T}, flag::UInt32, value::term_t
)::Bool where {T}
    v = PL_get_bool_ex(ld, value)
    v === nothing && return false
    if flag == TP_INCREMENTAL
        tbl_set_incremental_predicate(_query_gd(ld), def, v)
        return true
    else
        props = get_predicate_table_props!(def)
        if v
            props.flags |= flag
        else
            props.flags &= ~flag
        end
        return true
    end
end

# PORT: pl-tabling.c tbl_set_predicate_attribute
"Set the tabling attribute `att` of `def` from `value`: the tabling branch of `'\$set_predicate_attribute'/3` (pl-tabling.c)."
function tbl_set_predicate_attribute(
    ld::PL_local_data{T}, def::Definition{T}, att::T, value::term_t
)::Bool where {T}
    k = sym_key(att)
    if k == sym_key(mk_sym(T, :monotonic))
        return set_bool_attr(ld, def, TP_MONOTONIC, value)
    elseif k == sym_key(mk_sym(T, :incremental))
        return set_bool_attr(ld, def, TP_INCREMENTAL, value)
    elseif k == sym_key(mk_sym(T, :tshared))
        return set_bool_attr(ld, def, TP_SHARED, value)
    elseif k == sym_key(mk_sym(T, :opaque))
        return set_bool_attr(ld, def, TP_OPAQUE, value)
    elseif k == sym_key(mk_sym(T, :lazy))
        return set_bool_attr(ld, def, TP_LAZY, value)
    elseif k == sym_key(mk_sym(T, :tabled))
        return set_bool_attr(ld, def, TP_TABLED, value)
    elseif k == sym_key(mk_sym(T, :tabled_variant))
        return set_bool_attr(ld, def, TP_VARIANT, value)
    else
        p = get_predicate_table_props!(def)
        v = get_size_or_inf(ld, value)
        v === nothing && return false

        if k == sym_key(mk_sym(T, :abstract))
            p.abstract = v
        elseif k == sym_key(mk_sym(T, :subgoal_abstract))
            p.subgoal_abstract = v
        elseif k == sym_key(mk_sym(T, :answer_abstract))
            p.answer_abstract = v
        elseif k == sym_key(mk_sym(T, :max_answers))
            p.max_answers = v
        else
            return false
        end
    end
    return true
end

# PORT: pl-tabling.c BeginPredDefs as PL_predicates_from_tabling
# DIVERGES: the ported entries, in upstream's order (upstream's table has the other `$tbl_*` predicates; `$tbl_trienode`
# and `$tbl_is_trienode` sit between `$tbl_destroy_table/1` and `$tbl_delay_list/1`).
"pl-tabling.c's registration table (`BeginPredDefs(tabling)`): the ported entries."
const PL_predicates_from_tabling = (
    PL_extension("\$tbl_trienode", 1, pl_tbl_trienode1_va, PL_FA_VARARGS),
    PL_extension("\$tbl_is_trienode", 1, pl_tbl_is_trienode1_va, PL_FA_VARARGS)
)
