# UPSTREAM: swipl-devel src/pl-tabling.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  2017-2025, VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# allow-new-artifact: a 1:1 port of swipl-devel src/pl-tabling.c (the upstream file was read at the pin; capability search in evidence/TAB1MIN/handoff.md)
# PIN1 ledger (V10.1.20): re-cite only, no code change (cbf4e189..18168e62 compared, D-0447 Q1) — pl-tabling.c: the ported bodies are text-identical at the pin, the unported groups T1-T5 are the TAB1 row (cfile:pl-tabling.c, docs/r2_owners.tsv), S_TABLED stays the named refusal.
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

# TAB1 TB0 (the table state, in the order of pl-tabling.c): the constants of its file-level macros, the freed-object lists
# (`tbl_alloc`, `tbl_free`, `free_tbl_free_objects`), `initTabling!`, `setMonotonicMode`. The structs are in src/pl-incl.jl and
# src/pl-global.jl; `answer_delay_infos` is `gd.tabling_answer_delay_infos`. NOT PORTED, each to its owner: `node_delayinfo`,
# `set_node_delayinfo` (they read and set the node flag `TN_DELAYINFO` of TR1's trie node: TB4), `fast_ret_functor` and
# `cleanupTabling` (which clears it: TB3; its other half is the `O_PLMT` shared tables: TH1), `start_node_ids` (TB1), the IDG
# macros `IDG_CHANGED_*` (TB6), `wkl_step_state` and `TBL_ANSWER_*` (TB2/TB3, with the code that uses them).

# PORT: pl-tabling.c WL_GROUND
# DIVERGES: a sentinel INTEGER, upstream a pointer `(worklist *)0x21`: where a trie node's value says "ground", the kernel's
# node value (TR1) holds this number; `WL_IS_SPECIAL` tests its bit 0 as upstream does.
"The worklist value of a table with a ground call, a sentinel and no worklist (pl-tabling.c `WL_GROUND`)."
const WL_GROUND = 0x21
# PORT: pl-tabling.c WL_DYNAMIC
"The worklist value of a table of a dynamic predicate, a sentinel and no worklist (pl-tabling.c `WL_DYNAMIC`)."
const WL_DYNAMIC = 0x41

# PORT: pl-tabling.c WL_IS_SPECIAL
"Whether the worklist value `wl` is a sentinel (pl-tabling.c `WL_IS_SPECIAL`): its bit 0 is set."
WL_IS_SPECIAL(wl::Integer)::Bool = (Int(wl) & 0x1) != 0

# PORT: pl-tabling.c WL_IS_WORKLIST
"Whether the worklist value `wl` names a worklist (pl-tabling.c `WL_IS_WORKLIST`): neither NULL (0) nor a sentinel."
WL_IS_WORKLIST(wl::Integer)::Bool = wl != 0 && !WL_IS_SPECIAL(wl)

# PORT: pl-tabling.c WLFS_FREE_NONE
"`worklist_free` mode: free nothing (pl-tabling.c `WLFS_FREE_NONE`)."
const WLFS_FREE_NONE = 0x0000
# PORT: pl-tabling.c WLFS_KEEP_COMPLETE
"`worklist_free` mode: keep the complete tables (pl-tabling.c `WLFS_KEEP_COMPLETE`)."
const WLFS_KEEP_COMPLETE = 0x0001
# PORT: pl-tabling.c WLFS_FREE_ALL
"`worklist_free` mode: free every table (pl-tabling.c `WLFS_FREE_ALL`)."
const WLFS_FREE_ALL = 0x0002
# PORT: pl-tabling.c WLFS_DISCARD_INCOMPLETE
"`worklist_free` mode: discard the incomplete tables (pl-tabling.c `WLFS_DISCARD_INCOMPLETE`)."
const WLFS_DISCARD_INCOMPLETE = 0x0004

# PORT: pl-tabling.c DV_DELETED
# DIVERGES: the sentinel is an INTEGER trie index (upstream `(trie*)0x1`), TR1's index 0 being NULL and 1 never a real table
# when the sentinel is stored: the owners (TB4) read the field through this constant.
"The `delay.variant` of a deleted delay, a sentinel (pl-tabling.c `DV_DELETED`)."
const DV_DELETED = 1
# PORT: pl-tabling.c DL_UNDEFINED
"The delay list of an answer that is undefined, a sentinel (pl-tabling.c `DL_UNDEFINED`)."
const DL_UNDEFINED = 1
# PORT: pl-tabling.c DL_IS_DELAY_LIST
"Whether `dl` (0: none) is a delay list, not `DL_UNDEFINED` (pl-tabling.c `DL_IS_DELAY_LIST`)."
DL_IS_DELAY_LIST(dl::Integer)::Bool = dl != 0 && dl != DL_UNDEFINED

# PORT: pl-tabling.c CAND_UNDECIDED
"`wkl_step_state.candidates`: a new answer, its candidates not looked up (pl-tabling.c `CAND_UNDECIDED`)."
const CAND_UNDECIDED = 0
# PORT: pl-tabling.c CAND_ALL
"`wkl_step_state.candidates`: visit every suspension (pl-tabling.c `CAND_ALL`)."
const CAND_ALL = 1
# PORT: pl-tabling.c CAND_KEYED
"`wkl_step_state.candidates`: visit the members the index cursors are on (pl-tabling.c `CAND_KEYED`)."
const CAND_KEYED = 2

# PORT: pl-tabling.c TBL_FREE_COMPONENT
"The kind of the freed objects of a component (pl-tabling.c `TBL_FREE_COMPONENT`)."
const TBL_FREE_COMPONENT = 0
# PORT: pl-tabling.c TBL_FREE_WORKLIST_SET
"The kind of the freed objects of a worklist set (pl-tabling.c `TBL_FREE_WORKLIST_SET`)."
const TBL_FREE_WORKLIST_SET = 1
# PORT: pl-tabling.c TBL_FREE_WORKLIST
"The kind of the freed objects of a worklist (pl-tabling.c `TBL_FREE_WORKLIST`)."
const TBL_FREE_WORKLIST = 2
# PORT: pl-tabling.c TBL_FREE_CLUSTER
"The kind of the freed objects of a cluster (pl-tabling.c `TBL_FREE_CLUSTER`)."
const TBL_FREE_CLUSTER = 3
# PORT: pl-tabling.c TBL_FREE_KINDS
"The number of kinds of freed objects (pl-tabling.c `TBL_FREE_KINDS`)."
const TBL_FREE_KINDS = 4
# PORT: pl-tabling.c TBL_FREE_MAX
"The most freed objects of one kind a thread keeps (pl-tabling.c `TBL_FREE_MAX`)."
const TBL_FREE_MAX = 16

# ORIGINAL (TAB1 TB0): the vector of `ld.tabling.free_objects` of a kind, `kind` a `Val` of a `TBL_FREE_*` so that the answer's
# type is known; upstream indexes `list[kind]`.
tbl_free_list(fo::tbl_free_objects, ::Val{TBL_FREE_COMPONENT}) = fo.component
tbl_free_list(fo::tbl_free_objects, ::Val{TBL_FREE_WORKLIST_SET}) = fo.worklist_set
tbl_free_list(fo::tbl_free_objects, ::Val{TBL_FREE_WORKLIST}) = fo.worklist
tbl_free_list(fo::tbl_free_objects, ::Val{TBL_FREE_CLUSTER}) = fo.cluster

# PORT: pl-tabling.c tbl_alloc
# DIVERGES: the object is not allocated here: the caller builds a new one (`nothing` is upstream's `PL_malloc`, the caller's
# memset) when the list of its kind has none to reuse, and a reused one is reset by the caller, as upstream's (its first word
# was the link). `kind` is a `Val` of a `TBL_FREE_*`; `count[kind]` is the vector's length.
"A freed object of `kind` to reuse, or `nothing` (pl-tabling.c `tbl_alloc`)."
function tbl_alloc(ld::PL_local_data{T}, kind::Val) where {T}
    list = tbl_free_list(ld.tabling.free_objects, kind)
    isempty(list) && return nothing

    return pop!(list)
end

# PORT: pl-tabling.c tbl_free
# DIVERGES: as `tbl_alloc`; the object is dropped for Julia's collector (`PL_free`) when it is not kept.
"Keep the freed object `p` of `kind` for reuse unless `TBL_FREE_MAX` are kept already or the thread is closing (pl-tabling.c `tbl_free`)."
function tbl_free(ld::PL_local_data{T}, kind::Val, p)::Nothing where {T}
    fo = ld.tabling.free_objects
    list = tbl_free_list(fo, kind)
    if length(list) < TBL_FREE_MAX && !fo.closed
        push!(list, p)
    end

    return nothing
end

# PORT: pl-tabling.c free_tbl_free_objects
# DIVERGES: as `tbl_alloc`; the lists are emptied.
"Drop the freed objects of every kind; `closed` also stops `tbl_free` keeping any (pl-tabling.c `free_tbl_free_objects`)."
function free_tbl_free_objects(ld::PL_local_data{T}, closed::Bool)::Nothing where {T}
    fo = ld.tabling.free_objects
    empty!(fo.component)
    empty!(fo.worklist_set)
    empty!(fo.worklist)
    empty!(fo.cluster)
    closed && (fo.closed = true)

    return nothing
end

# PORT: pl-tabling.c initTabling
# DIVERGES: only the part that is state of one thread: the restraints (`LD->tabling.restraint.*`: `error` and unlimited) and
# `in_assert_propagation`; `answer_delay_infos` is made with the database (src/pl-setup.jl, `newHTablePP(64)`), the ten
# Prolog flags are `_init_tabling_flags!` (src/os/pl-prologflag.jl), `initIDGReaders()` and the `O_PLMT` shared mutex and
# condition variable are TB6 and TH1.
"Set the restraints of the thread to their defaults, `error` and unlimited (pl-tabling.c `initTabling`)."
function initTabling!(ld::PL_local_data{T})::Nothing where {T}
    r = ld.tabling.restraint
    err = mk_sym(T, :error)
    r.max_table_subgoal_size_action = err
    r.max_table_subgoal_size = -1
    r.max_table_answer_size_action = err
    r.max_table_answer_size = -1
    r.max_answers_for_subgoal_action = err
    r.max_answers_for_subgoal = -1
    r.max_incomplete_subgoals_action = err
    r.max_incomplete_subgoals = -1
    r.max_scc_subgoals_action = err
    r.max_scc_subgoals = -1
    ld.tabling.in_assert_propagation = false

    return nothing
end

# PORT: pl-tabling.c setMonotonicMode
# DIVERGES: the atom is `a`'s `sym_key` against `eager` and `lazy`; the error is `PL_error`'s with the culprit `a` put in a term.
"Set the flag `table_monotonic`: `eager` clears and `lazy` sets `TF_MONOTONIC_LAZY`, else `domain_error(table_monotonic, A)` (pl-tabling.c)."
function setMonotonicMode(ld::PL_local_data{T}, a::T)::Bool where {T}
    k = sym_key(a)
    if k == sym_key(mk_sym(T, :eager))
        ld.tabling.flags &= ~TF_MONOTONIC_LAZY
    elseif k == sym_key(mk_sym(T, :lazy))
        ld.tabling.flags |= TF_MONOTONIC_LAZY
    else
        value = PL_new_term_ref(ld)
        PL_put_atom(ld, value, a)
        return PL_error(ld, ERR_DOMAIN, mk_sym(T, :table_monotonic), value)
    end

    return true
end

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

# TAB1 TB8 (the restraint flags, the tripwires and the drop of intermediate tables; pl-tabling.c at 18168e629eab, in its order
# at :6340-6440 and :11693-11975). `tripwire_answers_for_subgoal` (:11827) and `pred_max_table_answer_size` are TB3's. The
# callers that TB1/TB2/TB3 refuse by name until this step stack: get_answer_table (`tbl_pred_tripwire`, TB1), tbl_add_answer_found
# (`tbl_wl_tripwire`, `add_radial_restraint`, `generalise_answer_substitution`, `add_answer_count_restraint`, TB3),
# `unify_table_status` (`tripwire_scc_subgoals`, TB1/TB2), `_unify_fresh_create` (`tripwire_incomplete_subgoals`, TB2),
# table_complete_all (`droppable_table`, `drop_intermediate_tables`, TB2): evidence/TB8/handoff.md lists each replacement.

# ORIGINAL (TAB1 TB8): whether the atom `a` is the atom `name`, by the atom's identity (`sym_key`), as upstream's `==` of atom handles.
"Whether the atom `a` is `name` (upstream: the comparison of two atom handles)."
_tbl_is(a::T, name::Symbol)::Bool where {T} = sym_key(a) == sym_key(mk_sym(T, name))

# ORIGINAL (TAB1 TB8): the atom (the blob term) that names the trie `tr`, `PL_put_atom(t, trie_symbol(tr))`'s value.
"The atom of the trie `tr`, made on first use (pl-trie.c `trie_symbol`)."
function _trie_atom(gd::PL_global_data{T}, tr::trie{T})::T where {T}
    return _blob_term!(gd.atoms, gd.atom_symbols, T, trie_symbol(gd, tr))
end

# PORT: pl-tabling.c unify_restraint
# DIVERGES: a `size_t` is an `Int`: `(size_t)-1` is -1; `PL_unify_uint64` of a non-negative value is `unify_int64_ex(t, i, true)`
# (pl-fli.c:3750-3755): a bound `t` that is no integer raises `type_error(integer, t)` (swipl 10.1.20:
# `current_prolog_flag(max_answers_for_subgoal, a)`).
"Unify `t` with the limit `val`: fail for no limit, -1 (pl-tabling.c)."
function unify_restraint(ld::PL_local_data{T}, t::term_t, val::Int)::Bool where {T}
    val == -1 && return false

    return unify_int64_ex(ld, t, val, true)
end

# PORT: pl-tabling.c tbl_get_restraint_flag
# DIVERGES: the key is compared by its atom (`_tbl_is`); upstream's -1 for a key that is no restraint flag (its caller tests
# `tbl_is_restraint_flag` first) is `false`.
"Unify `t` with the value of the restraint flag `key`; the three limits and the two others that are unlimited fail (pl-tabling.c)."
function tbl_get_restraint_flag(ld::PL_local_data{T}, t::term_t, key::T)::Bool where {T}
    r = ld.tabling.restraint
    if _tbl_is(key, :max_table_subgoal_size_action)
        return PL_unify_atom(ld, t, r.max_table_subgoal_size_action)
    elseif _tbl_is(key, :max_table_answer_size_action)
        return PL_unify_atom(ld, t, r.max_table_answer_size_action)
    elseif _tbl_is(key, :max_answers_for_subgoal_action)
        return PL_unify_atom(ld, t, r.max_answers_for_subgoal_action)
    elseif _tbl_is(key, :max_table_subgoal_size)
        return unify_restraint(ld, t, r.max_table_subgoal_size)
    elseif _tbl_is(key, :max_table_answer_size)
        return unify_restraint(ld, t, r.max_table_answer_size)
    elseif _tbl_is(key, :max_answers_for_subgoal)
        return unify_restraint(ld, t, r.max_answers_for_subgoal)
    elseif _tbl_is(key, :max_incomplete_subgoals_action)
        return PL_unify_atom(ld, t, r.max_incomplete_subgoals_action)
    elseif _tbl_is(key, :max_incomplete_subgoals)
        return unify_restraint(ld, t, r.max_incomplete_subgoals)
    elseif _tbl_is(key, :max_scc_subgoals_action)
        return PL_unify_atom(ld, t, r.max_scc_subgoals_action)
    elseif _tbl_is(key, :max_scc_subgoals)
        return unify_restraint(ld, t, r.max_scc_subgoals)
    end

    return false
end

# PORT: pl-tabling.c set_restraint_action
# DIVERGES: the action is returned (`nothing` after the error or a failed `PL_get_atom_ex`); upstream stores it through `valp`.
"The action atom `t` holds for the restraint `key`, or `nothing` after `domain_error(restraint_action, T)` (pl-tabling.c)."
function set_restraint_action(ld::PL_local_data{T}, t::term_t, key::T)::Union{Nothing, T} where {T}
    act = PL_get_atom_ex(ld, t)
    act === nothing && return nothing

    if _tbl_is(act, :error) || _tbl_is(act, :warning) || _tbl_is(act, :suspend)
        return act
    end

    _tbl_is(act, :complete_soundly) && (act = mk_sym(T, :bounded_rationality))      # XSB compatibility

    _tbl_is(key, :max_table_subgoal_size_action) && _tbl_is(act, :abstract) && return act
    if _tbl_is(key, :max_table_answer_size_action) && (_tbl_is(act, :bounded_rationality) || _tbl_is(act, :fail))
        return act
    end
    _tbl_is(key, :max_answers_for_subgoal_action) && _tbl_is(act, :bounded_rationality) && return act

    PL_error(ld, ERR_DOMAIN, mk_sym(T, :restraint_action), t)

    return nothing
end

# PORT: pl-tabling.c set_restraint
# DIVERGES: the limit is returned (`nothing` after the error); upstream stores it through `valp`. `infinite` is -1 and a size
# beyond `typemax(Int)` is `PL_get_size_ex`'s error.
"The limit `t` holds: `infinite` is -1, else a size (pl-tabling.c)."
function set_restraint(ld::PL_local_data{T}, t::term_t)::Union{Nothing, Int} where {T}
    inf = PL_get_atom(ld, t)
    (inf !== nothing && _tbl_is(inf, :infinite)) && return -1

    return PL_get_size_ex(ld, t)
end

# PORT: pl-tabling.c tbl_set_restraint_flag
# DIVERGES: the key is compared by its atom; upstream's -1 for a key that is no restraint flag (a truth value in C) cannot happen
# (the caller tests `tbl_is_restraint_flag` first) and is `true` here.
"Set the restraint flag `key` from `t`: the actions and limits of `LD->tabling.restraint` (pl-tabling.c)."
function tbl_set_restraint_flag(ld::PL_local_data{T}, t::term_t, key::T)::Bool where {T}
    r = ld.tabling.restraint
    if _tbl_is(key, :max_table_subgoal_size_action)
        a = set_restraint_action(ld, t, key)
        a === nothing && return false
        r.max_table_subgoal_size_action = a
    elseif _tbl_is(key, :max_table_answer_size_action)
        a = set_restraint_action(ld, t, key)
        a === nothing && return false
        r.max_table_answer_size_action = a
    elseif _tbl_is(key, :max_answers_for_subgoal_action)
        a = set_restraint_action(ld, t, key)
        a === nothing && return false
        r.max_answers_for_subgoal_action = a
    elseif _tbl_is(key, :max_table_subgoal_size)
        v = set_restraint(ld, t)
        v === nothing && return false
        r.max_table_subgoal_size = v
    elseif _tbl_is(key, :max_table_answer_size)
        v = set_restraint(ld, t)
        v === nothing && return false
        r.max_table_answer_size = v
    elseif _tbl_is(key, :max_answers_for_subgoal)
        v = set_restraint(ld, t)
        v === nothing && return false
        r.max_answers_for_subgoal = v
    elseif _tbl_is(key, :max_incomplete_subgoals_action)
        a = set_restraint_action(ld, t, key)
        a === nothing && return false
        r.max_incomplete_subgoals_action = a
    elseif _tbl_is(key, :max_incomplete_subgoals)
        v = set_restraint(ld, t)
        v === nothing && return false
        r.max_incomplete_subgoals = v
    elseif _tbl_is(key, :max_scc_subgoals_action)
        a = set_restraint_action(ld, t, key)
        a === nothing && return false
        r.max_scc_subgoals_action = a
    elseif _tbl_is(key, :max_scc_subgoals)
        v = set_restraint(ld, t)
        v === nothing && return false
        r.max_scc_subgoals = v
    end

    return true
end

# PORT: pl-tabling.c generalise_answer_substitution
# DIVERGES: the functor of the compound is its name and arity (`PL_get_name_arity`); `*p == ATOM_ret` is `ret` read through
# `PL_get_atom`.
"Unify `gen` with the most general `ret/N` term that fits `spec`, for the answer count restraint (pl-tabling.c)."
function generalise_answer_substitution(ld::PL_local_data{T}, spec::term_t, gen::term_t)::Bool where {T}
    if PL_is_compound(ld, spec)
        na = PL_get_name_arity(ld, spec)
        na === nothing && return false

        return PL_unify_functor(ld, gen, na[1], na[2])
    end
    a = PL_get_atom(ld, spec)
    (a !== nothing && _tbl_is(a, :ret)) && return PL_unify_atom(ld, gen, a)

    return PL_type_error(ld, "answer_substitution", spec)
end

# PORT: pl-tabling.c add_answer_count_restraint
# DIVERGES: the predicate is looked up by `lookupProcedure` (upstream: `_PL_predicate`, cached in `GD->procedures`); the
# database is `_query_gd(ld)`; the `DEBUG(MSG_TABLING_RESTRAINT)` print is left out.
"Add the condition `answer_count_restraint` to the current delay list: call `system:answer_count_restraint/0` (pl-tabling.c)."
function add_answer_count_restraint(ld::PL_local_data{T})::Bool where {T}
    gd = _query_gd(ld)
    pred = lookupProcedure(mk_sym(T, :answer_count_restraint), 0, MODULE_system(gd))

    return PL_call_predicate(gd, ld, nothing, PL_Q_PASS_EXCEPTION, pred, 0)
end

# PORT: pl-tabling.c add_radial_restraint
# DIVERGES: as `add_answer_count_restraint`, for `system:radial_restraint/0`.
"Add the condition `radial_restraint` to the current delay list: call `system:radial_restraint/0` (pl-tabling.c)."
function add_radial_restraint(ld::PL_local_data{T})::Bool where {T}
    gd = _query_gd(ld)
    pred = lookupProcedure(mk_sym(T, :radial_restraint), 0, MODULE_system(gd))

    return PL_call_predicate(gd, ld, nothing, PL_Q_PASS_EXCEPTION, pred, 0)
end

# PORT: pl-tabling.c tbl_wl_tripwire
# DIVERGES: `'$tabling':tripwire/3` is looked up by `lookupProcedure` (upstream: `_PL_predicate`, cached); the trie atom is
# `_trie_atom`; the `DEBUG(MSG_TABLING_RESTRAINT)` print is left out.
"Call `'\$tabling':tripwire(Wire, Action, Table)` for the answer table of the worklist `wl`: false if it fails or raises (pl-tabling.c)."
function tbl_wl_tripwire(ld::PL_local_data{T}, wl::tbl_worklist{T}, action::T, wire::T)::Bool where {T}
    gd = _query_gd(ld)
    pred = lookupProcedure(mk_sym(T, :tripwire), 3, lookupModule(gd, mk_sym(T, Symbol("\$tabling"))))
    av = PL_new_term_refs(ld, 3)

    return (
        PL_put_atom(ld, av, wire) &&
        PL_put_atom(ld, av + 1, action) &&
        PL_put_atom(ld, av + 2, _trie_atom(gd, wl_table(ld, wl))) &&
        PL_call_predicate(gd, ld, nothing, PL_Q_PASS_EXCEPTION, pred, av)
    )
end

# PORT: pl-tabling.c tbl_pred_tripwire
# DIVERGES: as `tbl_wl_tripwire`; `unify_definition(MODULE_user, av+2, def, 0, GP_QUALIFY)` takes the database.
"Call `'\$tabling':tripwire(Wire, Action, Pred)` for the predicate `def`: false if it fails or raises (pl-tabling.c)."
function tbl_pred_tripwire(ld::PL_local_data{T}, def::Definition{T}, action::T, wire::T)::Bool where {T}
    gd = _query_gd(ld)
    pred = lookupProcedure(mk_sym(T, :tripwire), 3, lookupModule(gd, mk_sym(T, Symbol("\$tabling"))))
    av = PL_new_term_refs(ld, 3)

    return (
        PL_put_atom(ld, av, wire) &&
        PL_put_atom(ld, av + 1, action) &&
        unify_definition(gd, ld, MODULE_user(gd), av + 2, def, 0, GP_QUALIFY) &&
        PL_call_predicate(gd, ld, nothing, PL_Q_PASS_EXCEPTION, pred, av)
    )
end

# PORT: pl-tabling.c tripwire_incomplete_subgoals
# DIVERGES: a `Definition` that is `nothing` is NULL.
"True unless the `max_incomplete_subgoals` limit is reached and its tripwire fails: the check before a table is created (pl-tabling.c)."
function tripwire_incomplete_subgoals(ld::PL_local_data{T}, def::Union{Nothing, Definition{T}})::Bool where {T}
    r = ld.tabling.restraint
    limit = r.max_incomplete_subgoals

    if limit != -1 && def !== nothing && ld.tabling.incomplete_tables == limit
        return tbl_pred_tripwire(ld, def, r.max_incomplete_subgoals_action, mk_sym(T, :max_incomplete_subgoals))
    end

    return true
end

# PORT: pl-tabling.c tripwire_scc_subgoals
"True unless a merge made the component of `wl` larger than `max_scc_subgoals` and its tripwire fails; `size0` is the size before (pl-tabling.c)."
function tripwire_scc_subgoals(ld::PL_local_data{T}, wl::tbl_worklist{T}, size0::Int)::Bool where {T}
    r = ld.tabling.restraint
    limit = r.max_scc_subgoals

    if limit != -1 && size0 <= limit && wls_size((wl.component::tbl_component{T}).created_worklists) > limit
        return tbl_wl_tripwire(ld, wl, r.max_scc_subgoals_action, mk_sym(T, :max_scc_subgoals))
    end

    return true
end

# PORT: pl-tabling.c TABLE_DROP_MIN_SIZE
"The smallest table (in bytes, `trie_table_size`) that `drop_intermediate_tables` drops (pl-tabling.c)."
const TABLE_DROP_MIN_SIZE = 1024

# PORT: pl-tabling.c droppable_table
# DIVERGES: the local data is an argument (`trie_symbol` needs the database; TB2's call `droppable_table(c, leader)` becomes
# `droppable_table(ld, c, leader)`); `PL_register_atom` is left out (no atom GC).
"Register the answer trie `atrie` as the table of the component `c` that may be dropped when the component completes (pl-tabling.c)."
function droppable_table(ld::PL_local_data{T}, c::tbl_component{T}, atrie::trie{T})::Nothing where {T}
    c.drop_symbol = _trie_atom(_query_gd(ld), atrie)
    c.drop_size = trie_table_size(atrie)
    c.drop_gen_calls = UInt64(atrie.gen_call)

    return nothing
end

# PORT: pl-tabling.c children_of_component
# DIVERGES: the pre-order buffer is a `Vector`.
"Append the completed children of the component `c` to `b` (pl-tabling.c)."
function children_of_component(c::tbl_component{T}, b::Vector{tbl_component{T}})::Nothing where {T}
    if c.children !== nothing
        for ch in c.children.members
            ch.status == SCC_COMPLETED && push!(b, ch)
        end
    end

    return nothing
end

# PORT: pl-tabling.c drop_intermediate_tables
# DIVERGES: `LD->tabling.variant_table` is the trie numbered `ld.tabling.variant_table` (0: none); `symbol_trie` is
# `trie_of_word` of the symbol's blob; `PL_unregister_atom` is left out (no atom GC); `table_is_incomplete` is TB1's.
"Drop the intermediate answer tables of the completed components below `root` that are cheap to recompute (pl-tabling.c)."
function drop_intermediate_tables(ld::PL_local_data{T}, root::tbl_component{T})::Nothing where {T}
    gd = _query_gd(ld)
    factor = Int64(ld.table_flags_drop_intermediate)
    vtrie = ld.tabling.variant_table != 0 ? gd.tries[ld.tabling.variant_table] : nothing   # private tables only

    order = tbl_component{T}[root]                  # pre-order
    i = 1
    while i <= length(order)
        children_of_component(order[i], order)
        i += 1
    end

    count = length(order)
    for k in count:-1:2                             # children first, not the root
        c = order[k]
        below = Int64(0)
        recompute = Int64(0)
        keep = true

        if c.children !== nothing
            for ch in c.children.members
                if ch.status == SCC_COMPLETED
                    below += ch.inferences
                    recompute += ch.drop_recompute
                end
            end
        end
        own = c.inferences > below ? c.inferences - below : Int64(0)
        recompute += own

        if c.drop_symbol !== nothing
            sym = c.drop_symbol::T
            atrie = is_blob(sym) ? trie_of_word(gd, blob_handle(sym)) : nothing

            keep = (
                atrie === nothing ||
                c.drop_size < TABLE_DROP_MIN_SIZE ||
                UInt64(atrie.gen_call) > c.drop_gen_calls ||
                recompute > factor * own
            )
            if !keep
                if vtrie !== nothing && !table_is_incomplete(atrie::trie{T})
                    trie_delete(vtrie, (atrie::trie{T}).variant, true)
                end
            end
            c.drop_symbol = nothing
        end
        c.drop_recompute = keep ? Int64(0) : recompute
    end

    return nothing
end

# TAB1 TB8 part 2: `'$tbl_sdg'/3` and `'$tbl_incomplete'/3` (pl-tabling.c:9526-9820 at the pin). The graph is built from the
# live objects: the components, tables and edges are insertion-ordered vectors with an `IdDict` as their index (upstream's
# `pair_map` iterates by hash: its tests `msort`), the handle of a worklist or a component is TB2's `tbl_pointer!`.

# PORT: pl-tabling.c sdg_atom
# DIVERGES: the enum and the `sdg_atoms[]` array are the symbols `null`, `positive`, `negative`, `pending`, `executing`,
# `delays`; `sdg_init` is not needed (`mk_sym` interns on first use, the functors are looked up where they are built).

# ORIGINAL (TAB1 TB8): upstream's `PL_put_pointer(t, obj)` (pl-fli.c) for a worklist or a component, 0 for NULL: the handle of
# TB2's `tbl_pointer!`.
"Put the handle of the worklist or component `obj` (0 for none) into `t` (pl-fli.c `PL_put_pointer`)."
function _tbl_put_pointer(
    ld::PL_local_data{T}, t::term_t, obj::Union{Nothing, tbl_worklist{T}, tbl_component{T}}
)::Bool where {T}
    return PL_put_int64(ld, t, obj === nothing ? 0 : tbl_pointer!(ld, obj))
end

# PORT: pl-tabling.c sdg_push_root
# DIVERGES: the stack is a `Vector` (no `segstack`, no `outOfCore`).
"Push the root of the component `c` on `stack` (pl-tabling.c `sdg_push_root`)."
function sdg_push_root(stack::Vector{tbl_component{T}}, c::tbl_component{T})::Nothing where {T}
    up = c.parent
    while up !== nothing
        c = up
        up = c.parent
    end
    push!(stack, c)

    return nothing
end

# PORT: pl-tabling.c sdg_collect
# DIVERGES: `components` and `tables` are insertion-ordered vectors with an `IdDict` for the lookup (upstream: two `pair_map`s,
# the count of a component being how often it was met); `c->children` is `component_set.members`; a table is a worklist whose
# `table` is not 0.
"Collect the active components below the roots on `stack` in `components` and their incomplete worklists in `tables` (pl-tabling.c)."
function sdg_collect(
    stack::Vector{tbl_component{T}}, components::Vector{tbl_component{T}}, seen::IdDict{tbl_component{T}, Bool},
    tables::Vector{tbl_worklist{T}}, tindex::IdDict{tbl_worklist{T}, Int}
)::Nothing where {T}
    while !isempty(stack)
        c = pop!(stack)

        c.status == SCC_ACTIVE || continue          # merged or completed
        haskey(seen, c) && continue                 # a root seen twice
        seen[c] = true
        push!(components, c)
        children = c.children
        if children !== nothing
            for ch in children.members
                push!(stack, ch)
            end
        end

        for wl in worklist_set_to_array(c.created_worklists, T)
            if wl.table != 0 && !haskey(tindex, wl)
                push!(tables, wl)
                tindex[wl] = length(tables)
            end
        end
    end

    return nothing
end

# PORT: pl-tabling.c sdg_count_edges
# DIVERGES: `tables` is the index of the tables (`tindex`, worklist -> position), `edges` the counts by (caller, callee, negative)
# with their order in `eorder`; the caller is the worklist `tbl_get_pointer` finds for the handle (upstream: a pointer, accepted
# only when it is in `tables`); `UNTNOT(sp->term)` is `sp.term`, the sign `IS_TNOT`'s field `is_tnot`.
"Count the suspensions on the callee `wl` by caller in `edges` (pl-tabling.c `sdg_count_edges`)."
function sdg_count_edges(
    ld::PL_local_data{T}, wl::tbl_worklist{T}, tindex::IdDict{tbl_worklist{T}, Int},
    edges::Dict{Tuple{Int, Int, Bool}, Int}, eorder::Vector{Tuple{Int, Int, Bool}}
)::Bool where {T}
    fid = PL_open_foreign_frame(ld)
    t = PL_new_term_ref(ld)
    a = PL_new_term_ref(ld)
    dependency = mk_sym(T, :dependency)

    c = wl.head
    while c !== nothing
        if c.type == CLUSTER_SUSPENSIONS
            for sp in c.suspensions
                if !PL_recorded(ld, sp.term, t)
                    PL_close_foreign_frame(ld, fid)

                    return false
                end
                if PL_is_functor(ld, t, dependency, 5) && _PL_get_arg(ld, 4, t, a)
                    caller = tbl_get_pointer(ld, a)
                    if caller isa tbl_worklist{T} && haskey(tindex, caller)
                        key = (tindex[caller], tindex[wl], sp.is_tnot)
                        if haskey(edges, key)
                            edges[key] += 1
                        else
                            edges[key] = 1
                            push!(eorder, key)
                        end
                    end
                end
                PL_rewind_foreign_frame(ld, fid)
            end
        end
        c = c.next
    end

    PL_close_foreign_frame(ld, fid)

    return true
end

# PORT: pl-tabling.c sdg_unify_table
# DIVERGES: the flags are consed in upstream's order (delays, executing, pending, negative), so the list reads [negative, pending,
# executing, delays]; the variant is read from the variant table of the thread (`atrie->data.variant` is a node of it).
"Unify `t` with table(Trie, Variant, SCC, Answers, Flags) of the worklist `wl` (pl-tabling.c `sdg_unify_table`)."
function sdg_unify_table(ld::PL_local_data{T}, t::term_t, wl::tbl_worklist{T})::Bool where {T}
    gd = _query_gd(ld)
    atrie = wl_table(ld, wl)
    av = PL_new_term_refs(ld, 6)
    flag = av + 5

    PL_put_atom(ld, av + 0, _trie_atom(gd, atrie)) || return false
    if atrie.variant != 0
        vtrie = gd.tries[ld.tabling.variant_table]
        unify_trie_term(ld, vtrie, atrie.variant, av + 1)[1] || return false
    end
    _tbl_put_pointer(ld, av + 2, wl.component) || return false
    PL_put_int64(ld, av + 3, atrie.value_count) || return false
    PL_put_nil(ld, av + 4)
    flags = (
        (!isempty(wl.delays), :delays), (wl.executing, :executing), (wl.in_global_wl, :pending), (wl.negative, :negative),
    )
    for (on, name) in flags
        if on
            PL_put_atom(ld, flag, mk_sym(T, name)) && PL_cons_list(ld, av + 4, flag, av + 4) || return false
        end
    end
    table5 = lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :table)), 5)

    return PL_cons_functor_v(ld, av + 0, table5, av) && PL_unify(ld, t, av + 0)
end

# PORT: pl-tabling.c tbl_sdg as pl_tbl_sdg3_va
# (pl-tabling.c:9667-9785 at the pin: PRED_IMPL("$tbl_sdg", 3, tbl_sdg, 0))
# DIVERGES: the single thread is the calling one; the components, tables and edges come in the order they are met (see above).
"`'\$tbl_sdg'(-Components, -Tables, -Edges)`: the subgoal dependency graph of the calling thread (pl-tabling.c)."
function pl_tbl_sdg3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    stack = tbl_component{T}[]
    components = tbl_component{T}[]
    seen = IdDict{tbl_component{T}, Bool}()
    tables = tbl_worklist{T}[]
    tindex = IdDict{tbl_worklist{T}, Int}()
    edges = Dict{Tuple{Int, Int, Bool}, Int}()
    eorder = Tuple{Int, Int, Bool}[]
    tail = PL_new_term_ref(ld)
    head = PL_new_term_ref(ld)
    av = PL_new_term_refs(ld, 4)
    gd = _query_gd(ld)

    active = ld.tabling.component
    active !== nothing && sdg_push_root(stack, active)
    s = ld.tabling.saved_status
    while s !== nothing
        root = s.scc
        root !== nothing && sdg_push_root(stack, root)
        s = s.prev
    end
    sdg_collect(stack, components, seen, tables, tindex)

    for wl in tables
        sdg_count_edges(ld, wl, tindex, edges, eorder) || return FFALSE
    end

    PL_put_term(ld, tail, A1)
    scc3 = lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :scc)), 3)
    for c in components
        parent = c.parent
        (
            PL_unify_list(ld, tail, head, tail) &&
                _tbl_put_pointer(ld, av + 0, c) &&
                (parent !== nothing ? _tbl_put_pointer(ld, av + 1, parent) : PL_put_atom(ld, av + 1, mk_sym(T, :null))) &&
                (
                    c.leader != 0 ? PL_put_atom(ld, av + 2, _trie_atom(gd, gd.tries[c.leader])) :
                    PL_put_atom(ld, av + 2, mk_sym(T, :null))
                ) &&
                PL_cons_functor_v(ld, av + 0, scc3, av) &&
                PL_unify(ld, head, av + 0)
        ) || return FFALSE
    end
    PL_unify_nil(ld, tail) || return FFALSE

    PL_put_term(ld, tail, A2)
    for wl in tables
        (PL_unify_list(ld, tail, head, tail) && sdg_unify_table(ld, head, wl)) || return FFALSE
    end
    PL_unify_nil(ld, tail) || return FFALSE

    PL_put_term(ld, tail, A3)
    edge4 = lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :edge)), 4)
    for key in eorder
        caller = tables[key[1]]
        callee = tables[key[2]]
        (
            PL_unify_list(ld, tail, head, tail) &&
                PL_put_atom(ld, av + 0, _trie_atom(gd, wl_table(ld, caller))) &&
                PL_put_atom(ld, av + 1, _trie_atom(gd, wl_table(ld, callee))) &&
                PL_put_atom(ld, av + 2, mk_sym(T, key[3] ? :negative : :positive)) &&
                PL_put_int64(ld, av + 3, edges[key]) &&
                PL_cons_functor_v(ld, av + 0, edge4, av) &&
                PL_unify(ld, head, av + 0)
        ) || return FFALSE
    end

    return PL_unify_nil(ld, tail) ? FTRUE : FFALSE
end

# ORIGINAL (TAB1 TB8): upstream's `PL_get_thread_id_ex(t, &tid)` (pl-thread.c); the kernel has the one thread `main` (thread id 1).
# swipl 10.1.20: `main` and 1 are the thread, another atom or integer raises `existence_error(thread, X)`, a variable
# `instantiation_error`, any other term `type_error(thread, X)`.
"Whether `t` names the one thread, `main` or 1; else raise the error of `PL_get_thread_id_ex` (pl-thread.c)."
function _tbl_get_thread_id_ex(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    a = PL_get_atom(ld, t)
    if a !== nothing
        _tbl_is(a, :main) && return true

        return PL_error(ld, ERR_EXISTENCE, mk_sym(T, :thread), t)
    end
    i = PL_get_int64(ld, t)
    if i !== nothing
        i == 1 && return true

        return PL_error(ld, ERR_EXISTENCE, mk_sym(T, :thread), t)
    end

    return PL_error(ld, ERR_TYPE, mk_sym(T, :thread), t)
end

# PORT: pl-tabling.c tbl_incomplete as pl_tbl_incomplete3_va
# (pl-tabling.c:9787-9820 at the pin: PRED_IMPL("$tbl_incomplete", 3, tbl_incomplete, 0))
# DIVERGES: the single thread (the `#else` of `O_PLMT`): the counters of the calling thread; `PL_unify_uint64` of a count is
# `unify_int64_ex(t, i, true)`.
"`'\$tbl_incomplete'(+Thread, -Tables, -SCCs)`: the number of incomplete tables and of active components of `Thread` (pl-tabling.c)."
function pl_tbl_incomplete3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    _tbl_get_thread_id_ex(ld, A1) || return FFALSE
    tables = ld.tabling.incomplete_tables
    sccs = ld.tabling.active_components

    return (unify_int64_ex(ld, A2, tables, true) && unify_int64_ex(ld, A3, sccs, true)) ? FTRUE : FFALSE
end

# PORT: pl-tabling.c BeginPredDefs as PL_predicates_from_tabling
# DIVERGES: the ported entries, in upstream's order (upstream's table has the other `$tbl_*` predicates; `$tbl_trienode`
# and `$tbl_is_trienode` sit between `$tbl_destroy_table/1` and `$tbl_delay_list/1`; `$tbl_sdg/3` and `$tbl_incomplete/3` sit after
# `$tbl_worklist_data/2` and before `$tbl_wkl_table/2`: the stack puts them there).
"pl-tabling.c's registration table (`BeginPredDefs(tabling)`): the ported entries."
const PL_predicates_from_tabling = (
    PL_extension("\$tbl_trienode", 1, pl_tbl_trienode1_va, PL_FA_VARARGS),
    PL_extension("\$tbl_is_trienode", 1, pl_tbl_is_trienode1_va, PL_FA_VARARGS),
    PL_extension("\$tbl_sdg", 3, pl_tbl_sdg3_va, PL_FA_VARARGS),
    PL_extension("\$tbl_incomplete", 3, pl_tbl_incomplete3_va, PL_FA_VARARGS)
)
