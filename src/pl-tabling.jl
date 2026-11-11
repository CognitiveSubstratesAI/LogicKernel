# UPSTREAM: swipl-devel src/pl-tabling.c @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-trie.c @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-trie.h @ 18168e629eab
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
const WL_GROUND = Int(0x21)
# PORT: pl-tabling.c WL_DYNAMIC
"The worklist value of a table of a dynamic predicate, a sentinel and no worklist (pl-tabling.c `WL_DYNAMIC`)."
const WL_DYNAMIC = Int(0x41)

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
# DIVERGES: the sentinel is an INTEGER trie index (upstream `(trie*)0x1`): -1, because every table trie is registered in
# `gd.tries` when it is made (`trie_serial!`, TB1; the variant table by `trie_symbol`), so the serial of a table trie is
# 1, 2, ... and NULL is 0: no table trie ever carries -1. The owners (TB4) read the field through this constant.
"The `delay.variant` of a deleted delay, a sentinel (pl-tabling.c `DV_DELETED`)."
const DV_DELETED = -1
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

# ORIGINAL (TAB1 TB1): the named refusal of the code of a pinned C function that belongs to a later step: the culprit is the
# function's name, `what` says which branch and `owner` is the step of docs/r2_owners.tsv that ports it.
"Refuse by name: throw the `NotPortedError` for the pinned C function `fname` (`what`: the branch), due in step `owner`."
function tbl_refuse(
    ::Type{T}, fname::Symbol, what::String, owner::String
)::Union{} where {T}
    throw(NotPortedError{T}(mk_sym(T, fname), what, owner))
end

# ---- TB1: the node cache of start nodes, the pointers to tries, the variant table (pl-tabling.c) ----

# PORT: pl-tabling.c new_node_array
# DIVERGES: a node_array is a `Vector{Int}` of node ids indexed by `start_id` (upstream: blocks of doubling size, never moved,
# so the array can be read without a lock: no concurrent readers here). `free_node_array` is dropping the vector (`ld.tabling.
# start_nodes = nothing`, by the owner of `clear_variant_table`, TB5).
"A new, empty node array (pl-tabling.c `new_node_array`)."
new_node_array()::Vector{Int} = Int[]

# PORT: pl-tabling.c start_node_id
# DIVERGES: the counter is `gd.tabling_start_node_ids` (upstream: a static, `ATOMIC_INC`).
"The id of the start node cache entry of the tabling properties `tp`, made at the first call (pl-tabling.c `start_node_id`)."
function start_node_id(gd::PL_global_data, tp::table_props)::UInt32
    id = tp.start_id
    if id == 0
        gd.tabling_start_node_ids += 1
        id = UInt32(gd.tabling_start_node_ids)
        tp.start_id = id
    end

    return id
end

# PORT: pl-tabling.c start_node_array
# DIVERGES: the private array of this thread only; the shared one (`GD->tabling.start_nodes`) is `O_PLMT`, owner TH1.
"The node array of the private tables of this thread, `nothing` until the first `set_start_node` (pl-tabling.c `start_node_array`)."
function start_node_array(
    ld::PL_local_data{T}, shared::Bool
)::Union{Nothing, Vector{Int}} where {T}
    shared && tbl_refuse(
        T,
        :start_node_array,
        "start_node_array(shared): the shared tables, `O_PLMT`",
        "TH1"
    )

    return ld.tabling.start_nodes
end

# PORT: pl-tabling.c get_start_node
# DIVERGES: a node id, 0 for NULL; the id is a 1-based index into the vector (`start_id` counts from 1, as upstream's).
"The cached start node id of `id` in the node array `a` (0: none), `a` may be `nothing` (pl-tabling.c `get_start_node`)."
function get_start_node(a::Union{Nothing, Vector{Int}}, id::Integer)::Int
    a === nothing && return 0
    id >= 1 && id <= length(a) && return a[id]

    return 0
end

# PORT: pl-tabling.c set_start_node
# DIVERGES: the array is `ld.tabling.start_nodes` (upstream `node_array **ap`) and grows by `resize!` (zero filled);
# `MAX_BLOCKS` is the only bound upstream has on the id and the vector has none. The node is pinned (`TN_PINNED`): an
# abolished table of the predicate does not prune the node. `tr` is the variant table the node belongs to.
"Cache `nid`, a node of the variant table `tr`, as the start node `id` of this thread and pin it (pl-tabling.c `set_start_node`)."
function set_start_node(
    ld::PL_local_data, tr::trie, id::Integer, nid::Int
)::Nothing
    a = ld.tabling.start_nodes
    if a === nothing
        a = new_node_array()
        ld.tabling.start_nodes = a
    end
    if id > length(a)
        old = length(a)
        resize!(a, Int(id))
        fill!(view(a, (old + 1):Int(id)), 0)
    end
    a[id] = nid
    tr.nodes[nid].flags |= TN_PINNED

    return nothing
end

# PORT: pl-trie.h TRIE_PTR_TAG
# DIVERGES: a node value that names a trie (the answer trie of a variant table node) is `(serial << 3) | 0x7`, `serial` the
# trie's number in `gd.tries` (upstream: the pointer with its low three bits set to `TRIE_PTR_TAG`, pl-trie.h:201-211).
# TAG_REFERENCE is also 7 but a trie node value never holds a reference, and `isRecord` (TR1: the low two bits are 0) is false.
"The low three bits of a node value that names a trie (pl-trie.h `TRIE_PTR_TAG`)."
const TRIE_PTR_TAG = UInt64(0x7)

# PORT: pl-trie.h isTriePtrValue
"Whether the node value `w` names a trie (pl-trie.h `isTriePtrValue`)."
isTriePtrValue(w::word)::Bool = (w & UInt64(0x7)) == TRIE_PTR_TAG

# PORT: pl-trie.h triePtrValue
# DIVERGES: the trie must be registered in the database (`trie_serial!`): its number is the value.
"The node value that names the registered trie `tr` (pl-trie.h `triePtrValue`)."
function triePtrValue(tr::trie)::word
    @assert tr.serial != 0
    return (UInt64(tr.serial) << 3) | TRIE_PTR_TAG
end

# PORT: pl-trie.h valueTriePtr
"The trie of the registry `registry` the node value `w` names (pl-trie.h `valueTriePtr`)."
valueTriePtr(registry::Vector{trie{T}}, w::word) where {T} = registry[Int(w >> 3)]

# ORIGINAL (TAB1 TB1): the registration of a trie in the database's table without making its symbol (upstream needs none: a
# trie is its own pointer); the number is what a pointer value names.
"Register `tr` in `gd.tries` unless it is registered; its number (pl-trie.h `triePtrValue` names a trie by it)."
function trie_serial!(gd::PL_global_data{T}, tr::trie{T})::Int where {T}
    if tr.serial == 0
        push!(gd.tries, tr)
        tr.serial = length(gd.tries)
    end

    return tr.serial
end

# PORT: pl-trie.c value_trie
"The trie a node value `w` names: a pointer value or the symbol atom of a trie (pl-trie.c `value_trie`)."
function value_trie(gd::PL_global_data{T}, w::word)::trie{T} where {T}
    isTriePtrValue(w) && return valueTriePtr(gd.tries, w)
    tr = symbol_trie(gd, w)
    tr === nothing && throw(ArgumentError("value_trie: the value names no trie"))

    return tr
end

# PORT: pl-tabling.c variant_table
# DIVERGES: the private table only (`O_PLMT` shared tables: `shared` is refused by name, owner TH1); the trie is made with
# `trie_create(T)`, no pool is used by the trie (the pool is kept in `ld.tabling.node_pool` as TB0 declares it); the table is
# `ld.tabling.variant_table`, the trie's number in `gd.tries`; `trie_symbol` is called as upstream's and registers the trie.
# `registry` is set on the table so that `release_node` finds the answer tries by number (TR1 field).
"The variant table of this thread (shared: of all threads): the trie that maps call variants to answer tables (pl-tabling.c)."
function variant_table(ld::PL_local_data{T}, shared::Bool)::trie{T} where {T}
    gd = _query_gd(ld)
    shared && tbl_refuse(
        T,
        :variant_table,
        "variant_table(shared): the shared variant table, `O_PLMT`",
        "TH1"
    )
    if ld.tabling.node_pool === nothing
        ld.tabling.node_pool = new_alloc_pool("private_table_space", gd.options.tableSpace)
    end

    if ld.tabling.variant_table == 0
        t = trie_create(T)
        t.flags |= TRIE_ISVARIANT
        trie_symbol(gd, t)
        t.registry = gd.tries
        ld.tabling.variant_table = t.serial
    end

    return gd.tries[ld.tabling.variant_table]
end

# PORT: pl-tabling.c RAT_CLEANUP
"`reset_answer_table` flag: clearing the variant table (pl-tabling.c `RAT_CLEANUP`)."
const RAT_CLEANUP = Int(0x1)
# PORT: pl-tabling.c RAT_BULK
"`reset_answer_table` flag: all private tables go (pl-tabling.c `RAT_BULK`)."
const RAT_BULK = Int(0x2)

# ORIGINAL (stack, batch 2): `trie_empty` and `trie_destroy` take the database since TR4 (`trie_discard_clause` retracts the compiled
# clause through it), but `release_node`, which reaches a table trie through `tbl_release_node` (and `release_value` through the
# pointer value of a variant table node), has none. A table trie holds no compiled clause before TB3 (`tbl_complete_answer_clause`),
# so these two do `empty_trie` and `trie_destroy` without the discard and refuse by name (owner TB3, which threads the database
# through `release_node`/`clear_node`) when `trie.clause` is set.
"`empty_trie` of a table trie without the database: refuses (owner TB3) a trie with a compiled clause."
function table_trie_empty(atrie::trie{T})::Nothing where {T}
    atrie.clause == 0 || tbl_refuse(
        T,
        :trie_discard_clause,
        "a table trie with a compiled clause (release_node has no database to retract it)",
        "TB3"
    )
    if atrie.references == 0
        clear_nodes(atrie, nothing)
        atrie.value_count = 0
        atrie.flags &= ~(TRIE_DISCARDABLE | TRIE_DISCARDED)
    end
    return nothing
end

"`trie_destroy` of a table trie without the database (see `table_trie_empty`)."
function table_trie_destroy(atrie::trie{T})::Nothing where {T}
    atrie.magic = TRIE_CMAGIC
    table_trie_empty(atrie)
    free_lingering_blocks(atrie)
    return nothing
end

# PORT: pl-tabling.c reset_answer_table
# DIVERGES: the worklist branch (an answer table with a worklist) is refused by name, owner TB2 (the worklists, the delays
# `destroy_depending_worklists`, `destroy_delay_info_worklist`, `free_worklist`); a sentinel (WL_GROUND, WL_DYNAMIC) is
# `data.worklist = Int` and is made fresh again; the IDG node is refused by name, owner TB6 (`idg_reset`, `idg_destroy`,
# `idg_destroy_private`), the tracked table (`tt_abolish_table`) owner TB9.
"Make the answer table `atrie` fresh again: no worklist, not complete, no answers (pl-tabling.c)."
function reset_answer_table(atrie::trie{T}, flags::Int)::Nothing where {T}
    wl = atrie.worklist
    if wl isa Int
        atrie.worklist = nothing                # make fresh again
    elseif wl !== nothing
        tbl_refuse(
            T,
            :reset_answer_table,
            "reset_answer_table: a table with a worklist (destroy_depending_worklists, free_worklist)",
            "TB2"
        )
    end
    atrie.flags &= ~TRIE_COMPLETE

    atrie.IDG === nothing || tbl_refuse(
        T,
        :reset_answer_table,
        "reset_answer_table: an IDG node (idg_reset, idg_destroy)",
        "TB6"
    )

    (atrie.flags & TRIE_ISTRACKED) != 0 && tbl_refuse(
        T,
        :tt_abolish_table,
        "reset_answer_table: a tracked table (tt_abolish_table)",
        "TB9"
    )

    table_trie_empty(atrie)

    return nothing
end

# PORT: pl-tabling.c release_variant_table_node
# DIVERGES: the answer trie is found by number in the table's `registry`; the node is a node id, the node's `variant` link
# of the answer trie is the node id (0: NULL).
"Release the answer table of node `nid` of the variant table `variant_table` (pl-tabling.c)."
function release_variant_table_node(variant_table::trie{T}, nid::Int)::Nothing where {T}
    node = variant_table.nodes[nid]
    if node.value != 0
        w = node.value
        atrie = if isTriePtrValue(w)
            valueTriePtr(variant_table.registry, w)
        else
            tbl_refuse(
                T,
                :release_variant_table_node,
                "release_variant_table_node: a symbol value, the shared tables",
                "TH1"
            )
        end
        reset_answer_table(atrie, variant_table.magic == TRIE_CMAGIC ? RAT_CLEANUP : 0)
        @assert atrie.variant == nid
        atrie.variant = 0
    end

    return nothing
end

# PORT: pl-tabling.c is_variant_trie
"Whether `tr` is a variant table (pl-tabling.c `is_variant_trie`)."
is_variant_trie(tr::trie)::Bool = (tr.flags & TRIE_ISVARIANT) != 0

# PORT: pl-tabling.c release_answer_node
# DIVERGES: a node with a delay list (`TN_DELAYINFO`: `destroy_delay_info`, `node_delayinfo`) is refused by name, owner TB4;
# no node has the flag before TB4.
"Release the tabling data of node `nid` of the answer trie `atrie` (pl-tabling.c)."
function release_answer_node(atrie::trie{T}, nid::Int)::Nothing where {T}
    if (atrie.nodes[nid].flags & TN_DELAYINFO) != 0
        tbl_refuse(
            T,
            :release_answer_node,
            "release_answer_node: a node with delay information (destroy_delay_info, set_node_delayinfo)",
            "TB4"
        )
    end

    return nothing
end

# PORT: pl-tabling.c tbl_release_node
"Called by the trie code when node `nid` of the answer trie or variant table `tr` is released (pl-tabling.c)."
function tbl_release_node(tr::trie{T}, nid::Int)::Nothing where {T}
    if is_variant_trie(tr)
        release_variant_table_node(tr, nid)
    else
        release_answer_node(tr, nid)
    end

    return nothing
end

# PORT: pl-tabling.c trie_ret_arity
# DIVERGES: the `O_TRIE_ATTVAR` branch (an attributed variable counts with its attribute, two entries for one argument) is TR3's:
# `vars` holds the positions of the variable cells and the arity is their number.
"The arity of the `ret/N` term of the variables `vars` (pl-tabling.c `trie_ret_arity`)."
trie_ret_arity(vars::Vector{Int})::Int = length(vars)

# PORT: pl-tabling.c ret_functor
# DIVERGES: the cache `fast_ret_functor` of the functors `ret/N` (the `VAR_SKEL_FAST` branch) is left out: this looks the functor up
# every time (`lookupFunctorDef`, a hash lookup), observable in nothing. TB0's note names TB3 as the owner of `cleanupTabling`,
# which clears the cache: with no cache there is nothing to clear.
"The functor word of `ret/arity` (pl-tabling.c `ret_functor`)."
function ret_functor(ld::PL_local_data{T}, arity::Int)::word where {T}
    return lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :ret)), arity)
end

# PORT: pl-tabling.c unify_trie_ret
# DIVERGES: `vars` is the vector of global POSITIONS of the variable cells (upstream: `Word` pointers in a TmpBuffer); a cell
# is an unbound variable here (a slot is never one), so each argument is a reference to it (`makeRefG`); no `GLOBAL_OVERFLOW`
# (a global stack that cannot grow is a resource error elsewhere), so the result is a `Bool`. The compound is put in a fresh
# term reference and unified with `ret` with `PL_unify` (upstream's `PL_unify_atomic` for a variable, `unify_ptrs` else).
"Unify `ret` with `ret(V1, ..., Vn)`, the variables `vars` of the call variant (pl-tabling.c `unify_trie_ret`)."
function unify_trie_ret(
    ld::PL_local_data{T}, ret::term_t, vars::Vector{Int}
)::Bool where {T}
    arity = trie_ret_arity(vars)
    @assert arity > 0
    vf = ret_functor(ld, arity)

    p = _alloc_compound!(ld, vf, arity)
    for (i, vp) in enumerate(vars)
        ld.gstack[p + i] = makeRefG(vp)
    end

    w = PL_new_term_ref(ld)
    ld.slots[w + 1] = consPtr(p, TAG_COMPOUND | STG_GLOBAL)

    return PL_unify(ld, ret, w)
end

# PORT: pl-tabling.c AT_CREATE
"`get_answer_table` flag: create the table if it does not exist (pl-tabling.c `AT_CREATE`)."
const AT_CREATE = Int(0x0001)
# PORT: pl-tabling.c AT_MODED
"`get_answer_table` flag: moded tabling, the trie has values (pl-tabling.c `AT_MODED`)."
const AT_MODED = Int(0x0002)
# PORT: pl-tabling.c AT_SHARED
"`get_answer_table` flag: find a shared table (pl-tabling.c `AT_SHARED`)."
const AT_SHARED = Int(0x0004)
# PORT: pl-tabling.c AT_PRIVATE
"`get_answer_table` flag: find a private table (pl-tabling.c `AT_PRIVATE`)."
const AT_PRIVATE = Int(0x0008)
# PORT: pl-tabling.c AT_NOCLAIM
"`get_answer_table` flag: do not claim ownership (pl-tabling.c `AT_NOCLAIM`)."
const AT_NOCLAIM = Int(0x0010)
# PORT: pl-tabling.c AT_ABSTRACT
"`get_answer_table` flag: `subgoal_abstract(N)` tabling (pl-tabling.c `AT_ABSTRACT`)."
const AT_ABSTRACT = Int(0x0020)
# PORT: pl-tabling.c AT_SCOPE_MASK
"`get_answer_table` flags that name the scope (pl-tabling.c `AT_SCOPE_MASK`)."
const AT_SCOPE_MASK = AT_SHARED | AT_PRIVATE

# PORT: pl-tabling.c pred_max_table_subgoal_size
# DIVERGES: `(size_t)-1` is -1 (as `table_props`).
"The subgoal size limit of `def`: its `subgoal_abstract`, else the restraint; -1: none (pl-tabling.c)."
function pred_max_table_subgoal_size(ld::PL_local_data, def::Definition)::Int
    limit = def.tabling !== nothing ? def.tabling.subgoal_abstract : -1
    if limit == -1
        limit = ld.tabling.restraint.max_table_subgoal_size
    end

    return limit
end

# PORT: pl-tabling.c get_answer_table
# DIVERGES: single thread: `shared` is false (the `O_PLMT` parts: the scope flags, `claim_answer_table`, the shared symbol, are
# TH1; a call with `AT_SHARED` or a predicate with `TP_SHARED` is refused by name); `def` is not looked up when it is
# `nothing` (upstream resolves the procedure of `t` only for the scope, which is the `O_PLMT` part). The size abstraction
# `sa` has `size` -1 (none) as `typemax(Int)`. The tripwire `tbl_pred_tripwire` (TB8) is refused by name unless the action
# is `abstract` and AT_ABSTRACT is set (that action needs no tripwire). The retry of upstream after a global stack overflow
# (`Undo`, `makeMoreStackSpace`) is not needed: no stack overflows here. A moded trie's `value_count` and the node's value
# are as upstream's; `clrefp` is the `O_PLMT` clause-reference protection (a trie clause is TR4): dropped.
"""
    get_answer_table(ld, def, t, ret, flags) -> Union{Nothing, trie}

Find the answer table of the variant `t` of the predicate `def` (`nothing` or the table) and unify `ret` with its `ret/N` skeleton;
with `AT_CREATE` create the table (pl-tabling.c).
"""
function get_answer_table(
    ld::PL_local_data{T}, def::Union{Nothing, Definition{T}}, t::term_t, ret::term_t,
    flags::Int
)::Union{Nothing, trie{T}} where {T}
    gd = _query_gd(ld)
    (flags & AT_SHARED) != 0 && tbl_refuse(
        T,
        :get_answer_table,
        "get_answer_table: AT_SHARED, a shared table (O_PLMT)",
        "TH1"
    )
    if def !== nothing && def.tabling !== nothing && (def.tabling.flags & TP_SHARED) != 0 &&
        (flags & AT_PRIVATE) == 0
        tbl_refuse(
            T,
            :get_answer_table,
            "get_answer_table: a shared tabled predicate (O_PLMT)",
            "TH1"
        )
    end

    size = def !== nothing ? pred_max_table_subgoal_size(ld, def) : -1
    variants = variant_table(ld, false)
    vars = Int[]

    sa = size_abstract(2, size == -1 ? typemax(Int) : size)
    rc, nid = trie_lookup_abstract(
        ld, variants, 0, -(t + 1), (flags & AT_CREATE) != 0, sa, vars
    )
    if rc <= 0
        trie_error(ld, rc, t)
        return nothing
    end

    if rc == TRIE_ABSTRACTED
        action = ld.tabling.restraint.max_table_subgoal_size_action
        if sym_key(action) == sym_key(mk_sym(T, :abstract)) && (flags & AT_ABSTRACT) == 0
            action = mk_sym(T, :error)
        end
        if sym_key(action) != sym_key(mk_sym(T, :abstract))
            # tbl_pred_tripwire(def, action, max_table_subgoal_size): the restraint tripwire is TB8
            tbl_refuse(
                T,
                :tbl_pred_tripwire,
                "get_answer_table: the subgoal size tripwire (tbl_pred_tripwire)",
                "TB8"
            )
        end
    end

    node = variants.nodes[nid]
    local atrie::trie{T}
    if node.value != 0
        atrie = value_trie(gd, node.value)
    elseif (flags & AT_CREATE) != 0
        atrie = trie_create(T)
        atrie.flags |= TRIE_ISTABLE | ((flags & AT_MODED) != 0 ? TRIE_ISMAP : TRIE_ISSET)
        atrie.predicate = def
        atrie.variant = nid
        atrie.registry = gd.tries
        trie_serial!(gd, atrie)

        node.flags |= TN_PRIMARY                    # symbol when needed
        node.value = triePtrValue(atrie)
        variants.value_count += 1                   # TRIE_COUNT_INC(variants, value_count)
    else
        return nothing
    end

    if ret != 0
        if isempty(vars)                            # TBD: only needed first time
            wl = atrie.worklist
            if wl isa tbl_worklist
                wl.ground = true
            elseif wl === nothing
                atrie.worklist = WL_GROUND
            end
            PL_unify_atom(ld, ret, mk_sym(T, :ret)) || return nothing
        else
            unify_trie_ret(ld, ret, vars) || return nothing
        end
    end

    return atrie
end

# PORT: pl-tabling.c unify_fresh
# DIVERGES: `create` true makes the component and the worklist of the table (`tripwire_incomplete_subgoals`: TB8,
# `tbl_create_subcomponent` and `tbl_add_worklist`: TB2) and is refused by name, owner TB2; `create` false is ported.
"Unify `t` with `fresh`, or with `fresh(SCC, WL)` when `create` (pl-tabling.c)."
function unify_fresh(
    ld::PL_local_data{T}, t::term_t, atrie::trie{T}, def::Union{Nothing, Definition{T}},
    create::Bool
)::Bool where {T}
    create && tbl_refuse(
        T,
        :unify_fresh,
        "unify_fresh(create): the component and worklist of a new table (tbl_create_subcomponent, tbl_add_worklist, tripwire_incomplete_subgoals)",
        "TB2"
    )

    return PL_unify_atom(ld, t, mk_sym(T, :fresh))
end

# PORT: pl-tabling.c complete_or_invalid_status
# DIVERGES: the IDG node (`atrie->data.IDG`, a monotonic or incremental table) is TB6's: refused by name when a table has one;
# no table has one before TB6, so the answer is `complete`.
"The status atom of a complete table: `complete`, `invalid` or `fresh` (pl-tabling.c)."
function complete_or_invalid_status(
    ld::PL_local_data{T}, atrie::trie{T}, create::Bool
)::T where {T}
    atrie.IDG === nothing || tbl_refuse(
        T,
        :complete_or_invalid_status,
        "complete_or_invalid_status: an IDG node (monotonic, falsecount, reevaluating)",
        "TB6"
    )

    return mk_sym(T, :complete)
end

# PORT: pl-tabling.c unify_complete_or_invalid
"Unify `t` with the status of the complete table `atrie` (pl-tabling.c)."
function unify_complete_or_invalid(
    ld::PL_local_data{T}, t::term_t, atrie::trie{T}, def::Union{Nothing, Definition{T}},
    create::Bool
)::Bool where {T}
    status = complete_or_invalid_status(ld, atrie, create)
    if sym_key(status) == sym_key(mk_sym(T, :fresh)) && create
        return unify_fresh(ld, t, atrie, def, create)
    else
        return PL_unify_atom(ld, t, status)
    end
end

# PORT: pl-tabling.c unify_table_status
# DIVERGES: a table with a worklist (`PL_unify_pointer(t, wl)`, `merge_component`, `tripwire_scc_subgoals`) is refused by name,
# owner TB2: no table has a worklist before TB2.
"Unify `t` with the status of `atrie`: `complete`, `invalid`, `dynamic` or `fresh`, a worklist for an incomplete table (pl-tabling.c)."
function unify_table_status(
    ld::PL_local_data{T}, t::term_t, atrie::trie{T}, def::Union{Nothing, Definition{T}},
    create::Bool
)::Bool where {T}
    if (atrie.flags & TRIE_COMPLETE) != 0
        return unify_complete_or_invalid(ld, t, atrie, def, create)
    else
        wl = atrie.worklist
        wl isa tbl_worklist && tbl_refuse(
            T,
            :unify_table_status,
            "unify_table_status: a table with a worklist (PL_unify_pointer, merge_component)",
            "TB2"
        )
        if wl isa Int && wl == WL_DYNAMIC
            return PL_unify_atom(ld, t, mk_sym(T, :dynamic))
        end

        @assert wl === nothing || wl == WL_GROUND
        return unify_fresh(ld, t, atrie, def, create)
    end
end

# PORT: pl-tabling.c table_status
"The status atom of `atrie`: `complete`, `invalid`, `incomplete`, `dynamic` or `fresh` (pl-tabling.c)."
function table_status(ld::PL_local_data{T}, atrie::trie{T})::T where {T}
    if (atrie.flags & TRIE_COMPLETE) != 0
        return complete_or_invalid_status(ld, atrie, false)
    else
        wl = atrie.worklist
        if wl isa tbl_worklist
            return mk_sym(T, :incomplete)
        elseif wl isa Int && wl == WL_DYNAMIC
            return mk_sym(T, :dynamic)
        else
            return mk_sym(T, :fresh)
        end
    end
end

# PORT: pl-tabling.c table_is_incomplete
"Whether `atrie` has a worklist and is not complete (pl-tabling.c)."
table_is_incomplete(atrie::trie)::Bool =
    atrie.worklist isa tbl_worklist && (atrie.flags & TRIE_COMPLETE) == 0

# PORT: pl-tabling.c unify_skeleton
# DIVERGES: `wrapper` 0 is NULL; the variant is found in this thread's variant table by the node id (`variant_table(false)`);
# the predicate of an incomplete table is the worklist's (`wl->predicate`, TB2: not met before it, so `nothing`).
"Unify `wrapper` with the variant of `atrie` and `skeleton` with its `ret/N` (pl-tabling.c)."
function unify_skeleton(
    ld::PL_local_data{T}, atrie::trie{T}, wrapper::term_t, skeleton::term_t
)::Bool where {T}
    wrapper == 0 && (wrapper = PL_new_term_ref(ld))

    if atrie.variant != 0
        ok, _ = unify_trie_term(
            ld,
            variant_table(ld, (atrie.flags & TRIE_ISSHARED) != 0),
            atrie.variant,
            wrapper
        )
        if ok
            wl = atrie.worklist
            def = wl isa tbl_worklist ? wl.predicate : nothing
            flags = (atrie.flags & TRIE_ISSHARED) != 0 ? AT_SHARED : AT_PRIVATE
            return get_answer_table(ld, def, wrapper, skeleton, flags | AT_NOCLAIM) !==
                   nothing
        end
    end

    return false
end

# PORT: pl-tabling.c tbl_variant_table
# DIVERGES: `clref` (the trie clause an O_PLMT build hands out for a complete table, `claim_answer_table`) is TR4's and is never
# set here: the table is always unified as symbol and `unify_table_status`. The closure-less call (`get_procedure(variant,
# GP_RESOLVE|GP_EXISTENCE_ERROR)`, e.g. `start_tabling(0, ...)`) is refused by name, owner TB2. `idg_init_variant` and
# `idg_add_edge` (TB6) are inlined as their guard: no IDG node and a predicate that is neither monotonic nor incremental
# needs nothing, else the name is refused (TB6); `inner_is_monotonic` (TB7) likewise.
"The common part of `'\$tbl_variant_table'/6` and its siblings: find or create the answer table of `variant` (pl-tabling.c)."
function tbl_variant_table(
    ld::PL_local_data{T}, closure::term_t, variant::term_t, Trie::term_t, abstract::term_t,
    status::term_t, ret::term_t, is_monotonic::term_t, flags::Int
)::Bool where {T}
    gd = _query_gd(ld)
    def = get_closure_predicate(gd, ld, closure)
    if def === nothing                          # e.g., start_tabling(0, ...)
        tbl_refuse(
            T,
            :get_procedure,
            "tbl_variant_table: no closure, get_procedure(GP_RESOLVE|GP_EXISTENCE_ERROR) of the variant",
            "TB2"
        )
    end

    atrie = get_answer_table(ld, def, variant, ret, flags)    # moded tabling needs the trie
    atrie === nothing && return false

    if atrie.IDG === nothing && def.tabling !== nothing &&
        (def.tabling.flags & (TP_MONOTONIC | TP_INCREMENTAL)) != 0
        tbl_refuse(
            T,
            :idg_init_variant,
            "tbl_variant_table: a monotonic or incremental table (idg_init_variant, idg_add_edge)",
            "TB6"
        )
    end
    atrie.IDG === nothing || tbl_refuse(
        T,
        :idg_add_edge,
        "tbl_variant_table: a table with an IDG node (idg_add_edge)",
        "TB6"
    )

    if is_monotonic != 0 && def.tabling !== nothing &&
        (def.tabling.flags & TP_MONOTONIC) != 0
        tbl_refuse(
            T,
            :inner_is_monotonic,
            "tbl_variant_table: a monotonic predicate (inner_is_monotonic)",
            "TB7"
        )
    end

    return unify_trie(gd, ld, Trie, atrie) &&
           unify_table_status(ld, status, atrie, def, true)
end

# PORT: pl-tabling.c tbl_variant_table as pl_tbl_variant_table6_va
# (PRED_IMPL("$tbl_variant_table", 6, tbl_variant_table, 0))
# DIVERGES: the create path reaches `unify_fresh(create)` and is refused by name, owner TB2 (a call that finds a complete table
# or an existing one does not).
"`'\$tbl_variant_table'(+Closure, +Variant, -Trie, -Status, -Skeleton, -IsMono)`: the table for `Variant` (pl-tabling.c)."
function pl_tbl_variant_table6_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3, A4, A5, A6 = PL__t0,
    PL__t0 + 1, PL__t0 + 2, PL__t0 + 3, PL__t0 + 4,
    PL__t0 + 5

    return tbl_variant_table(ld, A1, A2, A3, 0, A4, A5, A6, AT_CREATE) ? FTRUE : FFALSE
end

# PORT: pl-tabling.c tbl_abstract_table as pl_tbl_abstract_table6_va
# (PRED_IMPL("$tbl_abstract_table", 6, tbl_abstract_table, 0))
"`'\$tbl_abstract_table'(+Closure, :Wrapper, -Trie, -Abstract, -Status, -Skeleton)` (pl-tabling.c)."
function pl_tbl_abstract_table6_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3, A4, A5, A6 = PL__t0,
    PL__t0 + 1, PL__t0 + 2, PL__t0 + 3, PL__t0 + 4,
    PL__t0 + 5

    return if tbl_variant_table(ld, A1, A2, A3, A4, A5, A6, 0, AT_CREATE | AT_ABSTRACT)
        FTRUE
    else
        FFALSE
    end
end

# PORT: pl-tabling.c tbl_moded_variant_table as pl_tbl_moded_variant_table6_va
# (PRED_IMPL("$tbl_moded_variant_table", 6, tbl_moded_variant_table, 0))
"`'\$tbl_moded_variant_table'(+Closure, +Variant, -Trie, -Status, -Skeleton, -IsMono)` (pl-tabling.c)."
function pl_tbl_moded_variant_table6_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3, A4, A5, A6 = PL__t0,
    PL__t0 + 1, PL__t0 + 2, PL__t0 + 3, PL__t0 + 4,
    PL__t0 + 5

    return if tbl_variant_table(ld, A1, A2, A3, 0, A4, A5, A6, AT_CREATE | AT_MODED)
        FTRUE
    else
        FFALSE
    end
end

# PORT: pl-tabling.c tbl_existing_variant_table as pl_tbl_existing_variant_table5_va
# (PRED_IMPL("$tbl_existing_variant_table", 5, tbl_existing_variant_table, 0))
# DIVERGES: as `tbl_variant_table`: no `clref`; `get_closure_predicate` failing leaves `def` NULL as upstream (`nothing`).
"`'\$tbl_existing_variant_table'(+Closure, +Variant, -Trie, -Status, -Skeleton)`: the table for `Variant` if it exists (pl-tabling.c)."
function pl_tbl_existing_variant_table5_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    A1, A2, A3, A4, A5 = PL__t0, PL__t0 + 1, PL__t0 + 2, PL__t0 + 3, PL__t0 + 4
    def = get_closure_predicate(gd, ld, A1)

    atrie = get_answer_table(ld, def, A2, A5, 0)
    atrie === nothing && return FFALSE

    return if (
        unify_trie(gd, ld, A3, atrie) && unify_table_status(ld, A4, atrie, def, true)
    )
        FTRUE
    else
        FFALSE
    end
end

# PORT: pl-tabling.c tbl_local_variant_table as pl_tbl_local_variant_table1_va
# (PRED_IMPL("$tbl_local_variant_table", 1, tbl_local_variant_table, 0))
"`'\$tbl_local_variant_table'(-Trie)`: the variant table of this thread, if it has one (pl-tabling.c)."
function pl_tbl_local_variant_table1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    ld.tabling.variant_table == 0 && return FFALSE

    return unify_trie(gd, ld, PL__t0, gd.tries[ld.tabling.variant_table]) ? FTRUE : FFALSE
end

# PORT: pl-tabling.c tbl_global_variant_table as pl_tbl_global_variant_table1_va
# (PRED_IMPL("$tbl_global_variant_table", 1, tbl_global_variant_table, 0))
# DIVERGES: always fails: the shared variant table (`GD->tabling.variant_table`, `O_PLMT`) does not exist (owner TH1).
"`'\$tbl_global_variant_table'(-Trie)`: the shared variant table; none in a single thread (pl-tabling.c)."
function pl_tbl_global_variant_table1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return FFALSE
end

# PORT: pl-tabling.c tbl_variant_table as pl_tbl_variant_table1_va
# (PRED_IMPL("$tbl_variant_table", 1, tbl_variant_table, PL_FA_NONDETERMINISTIC), `O_PLMT` only)
# DIVERGES: deterministic: upstream returns the local table, then the shared one; there is no shared one (TH1), so there is at
# most one answer and no choice point is left.
"`'\$tbl_variant_table'(?Table)`: true when `Table` is a variant table (pl-tabling.c)."
function pl_tbl_variant_table1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    ld.tabling.variant_table == 0 && return FFALSE

    return unify_trie(gd, ld, PL__t0, gd.tries[ld.tabling.variant_table]) ? FTRUE : FFALSE
end

# PORT: pl-tabling.c tbl_table_status as pl_tbl_table_status2_va
# (PRED_IMPL("$tbl_table_status", 2, tbl_table_status, 0))
"`'\$tbl_table_status'(+Trie, -Status)`: the status of an answer table (pl-tabling.c)."
function pl_tbl_table_status2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    A1, A2 = PL__t0, PL__t0 + 1
    atrie = get_trie(gd, ld, A1)
    atrie === nothing && return FFALSE

    return unify_table_status(ld, A2, atrie, nothing, false) ? FTRUE : FFALSE
end

# PORT: pl-tabling.c tbl_table_status as pl_tbl_table_status4_va
# (PRED_IMPL("$tbl_table_status", 4, tbl_table_status, 0))
"`'\$tbl_table_status'(+Trie, -Status, -Wrapper, -Skeleton)`: the status of `Trie` and its wrapper and skeleton (pl-tabling.c)."
function pl_tbl_table_status4_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    A1, A2, A3, A4 = PL__t0, PL__t0 + 1, PL__t0 + 2, PL__t0 + 3
    wv = PL_new_term_ref(ld)
    atrie = get_trie(gd, ld, A1)
    atrie === nothing && return FFALSE

    return if (
        unify_table_status(ld, A2, atrie, nothing, false) &&
        unify_skeleton(ld, atrie, wv, A4) && PL_unify(ld, A3, wv)
    )
        FTRUE
    else
        FFALSE
    end
end

# PORT: pl-tabling.c tbl_table_pi as pl_tbl_table_pi2_va
# (PRED_IMPL("$tbl_table_pi", 2, tbl_table_pi, 0))
# DIVERGES: the variant is a node of this thread's variant table (the shared one is TH1); the term `Module:Name/Arity` is made
# with `PL_cons_functor` where upstream calls `PL_unify_term`; `atrie->data.variant` NULL (0) fails (upstream would read NULL).
"`'\$tbl_table_pi'(+ATrie, -PredicateIndicator)`: the predicate indicator of an answer trie (pl-tabling.c)."
function pl_tbl_table_pi2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    A1, A2 = PL__t0, PL__t0 + 1
    atrie = get_trie(gd, ld, A1)
    atrie === nothing && return FFALSE
    atrie.variant == 0 && return FFALSE

    av = PL_new_term_refs(ld, 3)
    wrapper, module_, head = av, av + 1, av + 2
    ok, _ = unify_trie_term(
        ld, variant_table(ld, (atrie.flags & TRIE_ISSHARED) != 0), atrie.variant, wrapper
    )
    ok || return FFALSE

    @assert PL_is_functor(ld, wrapper, mk_sym(T, :(:)), 2)
    _PL_get_arg(ld, 1, wrapper, module_)
    _PL_get_arg(ld, 2, wrapper, head)
    na = PL_get_name_arity(ld, head)
    na === nothing && return FFALSE
    name, arity = na

    r = PL_new_term_refs(ld, 3)
    PL_put_atom(ld, r, name)
    PL_put_integer(ld, r + 1, arity)
    fdiv = lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :/)), 2)
    PL_cons_functor(ld, r + 2, fdiv, r, r + 1)
    pi_ = PL_new_term_ref(ld)
    PL_cons_functor(ld, pi_, FUNCTOR_colon2, module_, r + 2)

    return PL_unify(ld, A2, pi_) ? FTRUE : FFALSE
end

# PORT: pl-tabling.c is_tabled
"Whether `def` is a tabled predicate (pl-tabling.c `is_tabled`)."
is_tabled(def::Definition)::Bool =
    def.tabling !== nothing && (def.tabling.flags & TP_TABLED) != 0

# PORT: pl-tabling.c tbl_implementation
# DIVERGES: the database and the local data are arguments; the qualified goal is made with `PL_cons_functor` where upstream
# calls `PL_unify_term`; `m` is the module's index (`PL_strip_module`).
"Unify `g` with the goal `g0` where it is defined; with `must_be_tabled` a permission error for a predicate that is not tabled (pl-tabling.c)."
function tbl_implementation(
    ld::PL_local_data{T}, g0::term_t, g::term_t, must_be_tabled::Bool
)::Bool where {T}
    gd = _query_gd(ld)
    t = PL_new_term_ref(ld)

    ok, mi = PL_strip_module(gd, ld, g0, 0, t)
    ok || return false
    f = PL_get_functor(ld, t)
    f === nothing && return PL_type_error(ld, "callable", g0)
    proc = resolveProcedure(gd, f[1], f[2], gd.modules[mi])

    isDefinedProcedure(gd, proc) || trapUndefined(gd, ld, proc.definition)
    def = proc.definition

    if must_be_tabled && !is_tabled(def)
        return PL_error(
            ld,
            ERR_PERMISSION_PROC,
            mk_sym(T, :tnot),
            mk_sym(T, :non_tabled_procedure),
            proc
        )
    end

    if def.module_ == mi
        return PL_unify(ld, g, g0)
    else
        mt = PL_new_term_ref(ld)
        PL_put_atom(ld, mt, gd.modules[def.module_].atom)
        r = PL_new_term_ref(ld)
        PL_cons_functor(ld, r, FUNCTOR_colon2, mt, t)
        return PL_unify(ld, g, r)
    end
end

# PORT: pl-tabling.c tnot_implementation as pl_tnot_implementation2_va
# (PRED_IMPL("$tnot_implementation", 2, tnot_implementation, PL_FA_TRANSPARENT))
"`'\$tnot_implementation'(:G0, -G)`: where `G0` is defined; an error if it is not tabled (pl-tabling.c)."
function pl_tnot_implementation2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return tbl_implementation(ld, PL__t0, PL__t0 + 1, true) ? FTRUE : FFALSE
end

# PORT: pl-tabling.c tbl_implementation as pl_tbl_implementation2_va
# (PRED_IMPL("$tbl_implementation", 2, tbl_implementation, PL_FA_TRANSPARENT))
"`'\$tbl_implementation'(:G0, -G)`: where `G0` is defined (pl-tabling.c)."
function pl_tbl_implementation2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return tbl_implementation(ld, PL__t0, PL__t0 + 1, false) ? FTRUE : FFALSE
end

# PORT: pl-tabling.c is_answer_trie as pl_is_answer_trie2_va
# (PRED_IMPL("$is_answer_trie", 2, is_answer_trie, 0))
# DIVERGES: an IDG node (`monotonic(How)`, `incremental`) is TB6's, refused by name; no table has one before it.
"`'\$is_answer_trie'(@Trie, -Type)`: `Trie` is an answer trie (possibly destroyed); its type (pl-tabling.c)."
function pl_is_answer_trie2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    A1, A2 = PL__t0, PL__t0 + 1
    atrie = get_trie_noex(gd, ld, A1)
    if atrie !== nothing && (atrie.flags & TRIE_ISTABLE) != 0
        wl = atrie.worklist
        if wl isa Int && wl == WL_DYNAMIC
            return PL_unify_atom(ld, A2, mk_sym(T, :dynamic)) ? FTRUE : FFALSE
        elseif atrie.IDG !== nothing
            tbl_refuse(
                T,
                :is_answer_trie,
                "is_answer_trie: an IDG node (monotonic(How), incremental)",
                "TB6"
            )
        else
            return PL_unify_atom(ld, A2, mk_sym(T, :normal)) ? FTRUE : FFALSE
        end
    end

    return FFALSE
end

# PORT: pl-tabling.c BeginPredDefs as PL_predicates_from_tabling
# DIVERGES: the ported entries, in upstream's order (upstream's table has the other `$tbl_*` predicates; `$tbl_trienode`
# and `$tbl_is_trienode` sit between `$tbl_destroy_table/1` and `$tbl_delay_list/1`). The TB1 entries are appended after them.
"pl-tabling.c's registration table (`BeginPredDefs(tabling)`): the ported entries."
const PL_predicates_from_tabling = (
    PL_extension("\$tbl_trienode", 1, pl_tbl_trienode1_va, PL_FA_VARARGS),
    PL_extension("\$tbl_is_trienode", 1, pl_tbl_is_trienode1_va, PL_FA_VARARGS),
    PL_extension("\$tbl_variant_table", 6, pl_tbl_variant_table6_va, PL_FA_VARARGS),
    PL_extension("\$tbl_abstract_table", 6, pl_tbl_abstract_table6_va, PL_FA_VARARGS),
    PL_extension(
        "\$tbl_moded_variant_table", 6, pl_tbl_moded_variant_table6_va, PL_FA_VARARGS
    ),
    PL_extension(
        "\$tbl_existing_variant_table", 5, pl_tbl_existing_variant_table5_va, PL_FA_VARARGS
    ),
    PL_extension(
        "\$tbl_local_variant_table", 1, pl_tbl_local_variant_table1_va, PL_FA_VARARGS
    ),
    PL_extension(
        "\$tbl_global_variant_table", 1, pl_tbl_global_variant_table1_va, PL_FA_VARARGS
    ),
    PL_extension("\$tbl_variant_table", 1, pl_tbl_variant_table1_va, PL_FA_VARARGS),
    PL_extension("\$tbl_table_status", 2, pl_tbl_table_status2_va, PL_FA_VARARGS),
    PL_extension("\$tbl_table_status", 4, pl_tbl_table_status4_va, PL_FA_VARARGS),
    PL_extension("\$tbl_table_pi", 2, pl_tbl_table_pi2_va, PL_FA_VARARGS),
    PL_extension(
        "\$tnot_implementation",
        2,
        pl_tnot_implementation2_va,
        PL_FA_TRANSPARENT | PL_FA_VARARGS
    ),
    PL_extension(
        "\$tbl_implementation",
        2,
        pl_tbl_implementation2_va,
        PL_FA_TRANSPARENT | PL_FA_VARARGS
    ),
    PL_extension("\$is_answer_trie", 2, pl_is_answer_trie2_va, PL_FA_VARARGS)
)
