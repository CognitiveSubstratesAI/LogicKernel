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

# PORT: pl-tabling.c BeginPredDefs as PL_predicates_from_tabling
# DIVERGES: the ported entries, in upstream's order (upstream's table has the other `$tbl_*` predicates; `$tbl_trienode`
# and `$tbl_is_trienode` sit between `$tbl_destroy_table/1` and `$tbl_delay_list/1`).
"pl-tabling.c's registration table (`BeginPredDefs(tabling)`): the ported entries."
const PL_predicates_from_tabling = (
    PL_extension("\$tbl_trienode", 1, pl_tbl_trienode1_va, PL_FA_VARARGS),
    PL_extension("\$tbl_is_trienode", 1, pl_tbl_is_trienode1_va, PL_FA_VARARGS)
)
