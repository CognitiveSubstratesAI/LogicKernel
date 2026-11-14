# UPSTREAM: swipl-devel src/pl-tabling.c @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-trie.c @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-trie.h @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-vmi.c @ 18168e629eab
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
const WLFS_FREE_NONE = Int(0x0000)
# PORT: pl-tabling.c WLFS_KEEP_COMPLETE
"`worklist_free` mode: keep the complete tables (pl-tabling.c `WLFS_KEEP_COMPLETE`)."
const WLFS_KEEP_COMPLETE = Int(0x0001)
# PORT: pl-tabling.c WLFS_FREE_ALL
"`worklist_free` mode: free every table (pl-tabling.c `WLFS_FREE_ALL`)."
const WLFS_FREE_ALL = Int(0x0002)
# PORT: pl-tabling.c WLFS_DISCARD_INCOMPLETE
"`worklist_free` mode: discard the incomplete tables (pl-tabling.c `WLFS_DISCARD_INCOMPLETE`)."
const WLFS_DISCARD_INCOMPLETE = Int(0x0004)

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

# TAB1 TB2 (worklists, components, completion; pl-tabling.c at 18168e629eab, in its order). The handle of a worklist or a
# component that Prolog sees is an index into `ld.tabling.pointers` (DIVERGES: upstream the address, `PL_unify_pointer`).
# Functions of later steps are named refusals (`NotPortedError`, owner TB3/TB4/TB5/TB6), never a wrong answer.

# ORIGINAL (TAB1 TB2): upstream's `PL_unify_pointer(t, wl)` makes the ADDRESS an integer; the kernel gives the object a
# handle, an index into `ld.tabling.pointers` (a freed slot is reused, as freed memory is).
"The handle of the worklist or component `obj` that Prolog sees (upstream: its address)."
function tbl_pointer!(
    ld::PL_local_data{T}, obj::Union{tbl_worklist{T}, tbl_component{T}}
)::Int where {T}
    obj.ptr != 0 && return obj.ptr
    tab = ld.tabling
    if isempty(tab.free_pointers)
        push!(tab.pointers, obj)
        i = length(tab.pointers)
    else
        i = pop!(tab.free_pointers)
        tab.pointers[i] = obj
    end
    obj.ptr = i

    return i
end

# ORIGINAL (TAB1 TB2): the handle of a freed object is freed with it (upstream: the address of freed memory).
"Free the handle of the worklist or component `obj` (upstream: its memory is freed)."
function tbl_pointer_release!(
    ld::PL_local_data{T}, obj::Union{tbl_worklist{T}, tbl_component{T}}
)::Nothing where {T}
    i = obj.ptr
    i == 0 && return nothing
    ld.tabling.pointers[i] = nothing
    push!(ld.tabling.free_pointers, i)
    obj.ptr = 0

    return nothing
end

# ORIGINAL (TAB1 TB2): upstream's `PL_unify_pointer(t, obj)` (pl-fli.c) for a worklist or a component.
"Unify `t` with the handle of the worklist or component `obj` (pl-fli.c `PL_unify_pointer`)."
function tbl_unify_pointer(
    ld::PL_local_data{T}, t::term_t, obj::Union{tbl_worklist{T}, tbl_component{T}}
)::Bool where {T}
    return PL_unify_int64(ld, t, tbl_pointer!(ld, obj))
end

# ORIGINAL (TAB1 TB2): upstream's `PL_get_pointer(t, &ptr)` (pl-fli.c:2461, an int64) followed by the cast; `nothing` when `t`
# is no integer or names no live object (upstream: a garbage pointer).
"The worklist or component whose handle is `t`, or `nothing` (pl-fli.c `PL_get_pointer`)."
function tbl_get_pointer(
    ld::PL_local_data{T}, t::term_t
)::Union{Nothing, tbl_worklist{T}, tbl_component{T}} where {T}
    i = PL_get_int64(ld, t)
    i === nothing && return nothing
    1 <= i <= length(ld.tabling.pointers) || return nothing

    return ld.tabling.pointers[i]
end

# ORIGINAL (TAB1 TB2): the answer trie of a worklist; upstream's `wl->table` is the pointer, the kernel's `wl.table` the trie's
# number in `gd.tries` (TB1, evidence/TB1/handoff.md item 1).
"The answer trie of the worklist `wl` (upstream `wl->table`)."
wl_table(ld::PL_local_data{T}, wl::tbl_worklist{T}) where {T} =
    _query_gd(ld).tries[wl.table]

# ORIGINAL (TAB1 TB2): the memset of a reused component (upstream `new_component`: `memset(c, 0, sizeof(*c))`, then the magic).
"Reset the reused component `c` to a new one (pl-tabling.c `new_component`'s memset)."
function _zero_component!(c::tbl_component{T})::tbl_component{T} where {T}
    c.magic = COMPONENT_MAGIC
    c.status = SCC_ACTIVE
    c.neg_status = SCC_NEG_NONE
    c.simplifications = 0
    c.parent = nothing
    c.children = nothing
    c.merged = nothing
    c.worklist = nothing
    c.created_worklists = nothing
    c.delay_worklists = nothing
    c.leader = 0
    c.inferences = 0
    c.drop_symbol = nothing
    c.drop_size = 0
    c.drop_gen_calls = UInt64(0)
    c.drop_recompute = 0
    c.ptr = 0

    return c
end

# PORT: pl-tabling.c new_component
# (pl-tabling.c:465-475 at the pin)
"A new active component (pl-tabling.c `new_component`): reused from the freed ones or made; counts `active_components`."
function new_component(ld::PL_local_data{T})::tbl_component{T} where {T}
    r = tbl_alloc(ld, Val(TBL_FREE_COMPONENT))
    c = r === nothing ? tbl_component{T}() : _zero_component!(r)    # memset; c->magic = COMPONENT_MAGIC
    ld.tabling.active_components += 1

    return c
end

# PORT: pl-tabling.c set_component_status
# (pl-tabling.c:477-488 at the pin)
"Set the status of `c`, keeping `active_components` the number of components with `SCC_ACTIVE` (pl-tabling.c)."
function set_component_status(
    ld::PL_local_data{T}, c::tbl_component{T}, status::Int
)::Nothing where {T}
    if c.status == SCC_ACTIVE && status != SCC_ACTIVE
        ld.tabling.active_components -= 1           # assert(LD->tabling.active_components > 0)
    elseif c.status != SCC_ACTIVE && status == SCC_ACTIVE
        ld.tabling.active_components += 1
    end
    c.status = status

    return nothing
end

# PORT: pl-tabling.c uncount_created_worklists
# (pl-tabling.c:490-496 at the pin)
"Take the worklists of `wls` off `incomplete_tables` (pl-tabling.c `uncount_created_worklists`)."
function uncount_created_worklists(
    ld::PL_local_data{T}, wls::worklist_set{tbl_worklist{T}}
)::Nothing where {T}
    ld.tabling.incomplete_tables -= length(wls.members)    # assert(ld->tabling.incomplete_tables >= n)

    return nothing
end

# PORT: pl-tabling.c FC_DESTROY
"`free_components_set` frees the members too (pl-tabling.c `FC_DESTROY`)."
const FC_DESTROY = Int(0x0001)
# PORT: pl-tabling.c FC_CHILD
"`free_component` of a child: it is not taken off its parent (pl-tabling.c `FC_CHILD`)."
const FC_CHILD = Int(0x0002)

# PORT: pl-tabling.c push_component_set
# (pl-tabling.c:501-514 at the pin)
# DIVERGES: the `segstack` is a vector; `PL_free(cs)` is emptying it (Julia's collector frees it).
"Push the members of `cs` on `stack` and free the set (pl-tabling.c `push_component_set`)."
function push_component_set(
    stack::Vector{tbl_component{T}}, cs::component_set{tbl_component{T}}
)::Nothing where {T}
    append!(stack, cs.members)
    empty!(cs.members)                              # discardBuffer(&cs->members); PL_free(cs)

    return nothing
end

# PORT: pl-tabling.c free_component
# (pl-tabling.c:516-560 at the pin)
# DIVERGES: `PL_unregister_atom(c->drop.symbol)` is not done (the kernel's atoms have no reference counts, audit D-0453
# item 5); the handle of each freed component is freed (`tbl_pointer_release!`).
"Free the component `c`, its children and merged components (pl-tabling.c `free_component`)."
function free_component(
    ld::PL_local_data{T}, c::tbl_component{T}, flags::Int
)::Nothing where {T}
    c.magic = 0                                     # assert(c->magic == COMPONENT_MAGIC)
    if c === ld.tabling.component
        ld.tabling.component = c.parent
        if c.parent === nothing && ld.tabling.has_scheduling_component
            ld.tabling.has_scheduling_component = false
        end
    end

    stack = tbl_component{T}[c]                     # initSegStack(); pushSegStack(&stack, c)
    while !isempty(stack)
        c = pop!(stack)
        cparent = c.parent                          # read once: the check and the call see the same parent
        if (flags & FC_CHILD) == 0 && cparent !== nothing
            del_child_component(cparent, c)
        end
        flags |= FC_CHILD                           # only for the first

        cwl = c.worklist
        cwl !== nothing && free_worklist_set(ld, cwl, Int(WLFS_FREE_NONE))
        cdl = c.delay_worklists
        cdl !== nothing && free_worklist_set(ld, cdl, Int(WLFS_FREE_NONE))
        ccw = c.created_worklists
        if ccw !== nothing
            uncount_created_worklists(ld, ccw)
            free_worklist_set(ld, ccw, Int(WLFS_FREE_ALL))
        end
        c.status == SCC_ACTIVE && set_component_status(ld, c, SCC_COMPLETED)
        cch = c.children
        cch !== nothing && push_component_set(stack, cch)
        cme = c.merged
        cme !== nothing && push_component_set(stack, cme)
        tbl_pointer_release!(ld, c)
        tbl_free(ld, Val(TBL_FREE_COMPONENT), c)
    end

    return nothing
end

# PORT: pl-tabling.c add_child_component
# (pl-tabling.c:563-574 at the pin)
"Add `child` to the children of `parent` (pl-tabling.c `add_child_component`)."
function add_child_component(
    parent::tbl_component{T}, child::tbl_component{T}
)::Nothing where {T}
    cs = parent.children
    if cs === nothing
        cs = component_set{tbl_component{T}}()
        parent.children = cs
    end
    push!(cs.members, child)

    return nothing
end

# PORT: pl-tabling.c del_child_component
# (pl-tabling.c:576-591 at the pin)
"Take `child` off the children of `parent`, if it is there (it can be merged; pl-tabling.c `del_child_component`)."
function del_child_component(
    parent::tbl_component{T}, child::tbl_component{T}
)::Nothing where {T}
    cs = parent.children
    if cs !== nothing                               # can be merged
        i = findfirst(m -> m === child, cs.members)
        i === nothing || deleteat!(cs.members, i)   # memmove(); popBuffer()
    end

    return nothing
end

# PORT: pl-tabling.c free_components_set
# (pl-tabling.c:593-605 at the pin)
"Free the set `cs`; with `FC_DESTROY` its members too (pl-tabling.c `free_components_set`)."
function free_components_set(
    ld::PL_local_data{T}, cs::component_set{tbl_component{T}}, flags::Int
)::Nothing where {T}
    if (flags & FC_DESTROY) != 0
        for m in cs.members
            free_component(ld, m, flags)
        end
    end
    empty!(cs.members)                              # discardBuffer(&cs->members); PL_free(cs)

    return nothing
end

# PORT: pl-tabling.c wls_size
# (pl-tabling.c:616-619 at the pin)
"The number of worklists in `wls`, 0 for none (pl-tabling.c `wls_size`)."
wls_size(wls::Union{Nothing, worklist_set}) = wls === nothing ? 0 : length(wls.members)

# PORT: pl-tabling.c merge_component
# (pl-tabling.c:622-636 at the pin)
"Merge the active subcomponents of `c` into `c` and make `c` the component of their worklists (pl-tabling.c `merge_component`)."
function merge_component(ld::PL_local_data{T}, c::tbl_component{T})::Nothing where {T}
    s_global = wls_size(c.worklist)
    s_created = wls_size(c.created_worklists)

    c.children !== nothing && merge_children(ld, c, c)
    wls_set_component(ld, c.worklist, s_global, c)
    wls_set_component(ld, c.created_worklists, s_created, c)

    return nothing
end

# PORT: pl-tabling.c wl_set_component
# (pl-tabling.c:639-654 at the pin)
"Make `c` the component of `wl`; schedule it when it has work; a negative node makes `c` delay (pl-tabling.c `wl_set_component`)."
function wl_set_component(
    ld::PL_local_data{T}, wl::tbl_worklist{T}, c::tbl_component{T}
)::Nothing where {T}
    wl.component = c
    wl.executing = false
    if !wl.in_global_wl && wl_has_work(wl)
        add_global_worklist(ld, wl)
    end
    if wl.negative
        if c.neg_status == SCC_NEG_NONE
            c.neg_status = SCC_NEG_DELAY
        elseif c.neg_status == SCC_NEG_SIMPLIFY
            c.neg_status = SCC_NEG_DELAY
        end
    end

    return nothing
end

# PORT: pl-tabling.c wls_set_component
# (pl-tabling.c:657-675 at the pin; the non-O_DEBUG branch)
# DIVERGES: an absent set (`nothing`) does nothing; upstream reads `wls->members` of it.
"Make `c` the component of the worklists of `wls` after the first `size0` (pl-tabling.c `wls_set_component`)."
function wls_set_component(
    ld::PL_local_data{T}, wls::Union{Nothing, worklist_set{tbl_worklist{T}}}, size0::Int,
    c::tbl_component{T}
)::Nothing where {T}
    wls === nothing && return nothing
    members = wls.members
    i = size0 + 1                                   # base += size0: skip old ones
    while i <= length(members)
        wl_set_component(ld, members[i], c)
        i += 1
    end

    return nothing
end

# PORT: pl-tabling.c merge_component_sets
# (pl-tabling.c:677-693 at the pin)
# DIVERGES: upstream sets `*into` and clears `*from` through pointers; this returns the new `into`, the caller sets it and
# clears `from` (it is NULL afterwards in every branch).
"Move the members of `from` into `into`, the set that remains (pl-tabling.c `merge_component_sets`)."
function merge_component_sets(
    ld::PL_local_data{T}, into::Union{Nothing, component_set{tbl_component{T}}},
    from::Union{Nothing, component_set{tbl_component{T}}}
)::Union{Nothing, component_set{tbl_component{T}}} where {T}
    if into !== nothing && from !== nothing
        append!(into.members, from.members)         # addMultipleBuffer()
        free_components_set(ld, from, 0)
        return into
    elseif from !== nothing
        return from
    end

    return into
end

# PORT: pl-tabling.c merge_children
# (pl-tabling.c:698-711 at the pin)
"Merge the children of `m`, recursively, into `c` (pl-tabling.c `merge_children`)."
function merge_children(
    ld::PL_local_data{T}, c::tbl_component{T}, m::tbl_component{T}
)::Nothing where {T}
    cs = m.children
    if cs !== nothing
        for child in cs.members
            merge_one_component(ld, c, child)
        end
        m.merged = merge_component_sets(ld, m.merged, m.children)  # merge_component_sets(&m->merged, &m->children)
        m.children = nothing
    end

    return nothing
end

# PORT: pl-tabling.c merge_worklists
# (pl-tabling.c:714-730 at the pin)
# DIVERGES: as `merge_component_sets`: returns the new `into`; the caller clears `from`.
"Move the worklists of `from` into `into`, the set that remains (pl-tabling.c `merge_worklists`)."
function merge_worklists(
    ld::PL_local_data{T}, into::Union{Nothing, worklist_set{tbl_worklist{T}}},
    from::Union{Nothing, worklist_set{tbl_worklist{T}}}
)::Union{Nothing, worklist_set{tbl_worklist{T}}} where {T}
    if into !== nothing && from !== nothing
        append!(into.members, from.members)         # addMultipleBuffer()
        free_worklist_set(ld, from, Int(WLFS_FREE_NONE))
        return into
    elseif from !== nothing
        return from
    end

    return into
end

# PORT: pl-tabling.c merge_one_component
# (pl-tabling.c:733-753 at the pin)
"Merge the active component `m` and its children into `c`; `m` becomes `SCC_MERGED` (pl-tabling.c `merge_one_component`)."
function merge_one_component(
    ld::PL_local_data{T}, c::tbl_component{T}, m::tbl_component{T}
)::Nothing where {T}
    # assert(m->magic == COMPONENT_MAGIC)
    m.status != SCC_ACTIVE && return nothing

    merge_children(ld, c, m)
    c.worklist = merge_worklists(ld, c.worklist, m.worklist)
    m.worklist = nothing
    c.created_worklists = merge_worklists(ld, c.created_worklists, m.created_worklists)
    m.created_worklists = nothing
    c.delay_worklists = merge_worklists(ld, c.delay_worklists, m.delay_worklists)
    m.delay_worklists = nothing
    set_component_status(ld, m, SCC_MERGED)

    return nothing
end

# PORT: pl-tabling.c new_worklist_set
# (pl-tabling.c:759-767 at the pin)
"A new set holding the worklist `wl` (pl-tabling.c `new_worklist_set`)."
function new_worklist_set(
    ld::PL_local_data{T}, wl::tbl_worklist{T}
)::worklist_set{tbl_worklist{T}} where {T}
    r = tbl_alloc(ld, Val(TBL_FREE_WORKLIST_SET))
    wls = r === nothing ? worklist_set{tbl_worklist{T}}() : r
    empty!(wls.members)                             # initBuffer(&wls->members)
    push!(wls.members, wl)

    return wls
end

# PORT: pl-tabling.c add_global_worklist
# (pl-tabling.c:770-781 at the pin)
"Schedule `wl` on the worklist of its component (pl-tabling.c `add_global_worklist`)."
function add_global_worklist(ld::PL_local_data{T}, wl::tbl_worklist{T})::Nothing where {T}
    c = wl.component::tbl_component{T}
    wls = c.worklist
    if wls === nothing
        c.worklist = new_worklist_set(ld, wl)
    else
        push!(wls.members, wl)
    end
    wl.in_global_wl = true

    return nothing
end

# PORT: pl-tabling.c add_delay_worklist
# (pl-tabling.c:784-793 at the pin)
"Add `wl` to the worklists of its component that need delays (pl-tabling.c `add_delay_worklist`)."
function add_delay_worklist(ld::PL_local_data{T}, wl::tbl_worklist{T})::Nothing where {T}
    c = wl.component::tbl_component{T}
    wls = c.delay_worklists
    if wls === nothing
        c.delay_worklists = new_worklist_set(ld, wl)
    else
        push!(wls.members, wl)
    end

    return nothing
end

# PORT: pl-tabling.c negative_worklist
# (pl-tabling.c:803-846 at the pin; the non-O_DEBUG branch)
# DIVERGES: `simplify_component` returns a Bool (`ok`, as TB4 ports it); the result is not read, as upstream's call is a statement.
"The next suspended negation of `scc` to resume with an empty answer cluster, or `nothing` once all are done (pl-tabling.c `negative_worklist`)."
function negative_worklist(
    ld::PL_local_data{T}, scc::tbl_component{T}
)::Union{Nothing, tbl_worklist{T}} where {T}
    dwls = scc.delay_worklists
    if dwls !== nothing
        while !isempty(dwls.members)
            wl = pop!(dwls.members)
            if !wl.has_answers                      # we have an unconditional answers, so no delay
                wl.neg_delayed = true
                c = new_answer_cluster(ld, wl, answer(0))   # answer ans = {NULL}
                wkl_append_left(wl, c)
                wl.riac === nothing && (wl.riac = c)
                return wl
            end
        end
        scc.neg_status = SCC_NEG_SIMPLIFY
    end

    simplify_component(ld, scc)
    return nothing
end

# PORT: pl-tabling.c wl_has_work
# (pl-tabling.c:849-852 at the pin)
"Whether `wl` has an answer cluster left of a suspension cluster (pl-tabling.c `wl_has_work`)."
wl_has_work(wl::tbl_worklist{T}) where {T} =
    (riac=wl.riac; riac !== nothing && riac.next !== nothing)

# PORT: pl-tabling.c pop_worklist
# (pl-tabling.c:855-870 at the pin)
"The next scheduled worklist of `c` that has work, or `nothing` (pl-tabling.c `pop_worklist`)."
function pop_worklist(
    ld::PL_local_data{T}, c::tbl_component{T}
)::Union{Nothing, tbl_worklist{T}} where {T}
    wls = c.worklist
    if wls !== nothing
        while !isempty(wls.members)
            wl = pop!(wls.members)
            wl.in_global_wl = false
            wl_has_work(wl) && return wl
        end
    end

    return nothing
end

# PORT: pl-tabling.c reset_global_worklist
# (pl-tabling.c:873-881 at the pin)
"Drop the scheduled worklists of `c` (pl-tabling.c `reset_global_worklist`)."
function reset_global_worklist(
    ld::PL_local_data{T}, c::Union{Nothing, tbl_component{T}}
)::Nothing where {T}
    if c !== nothing
        wls = c.worklist
        if wls !== nothing
            c.worklist = nothing
            free_worklist_set(ld, wls, Int(WLFS_FREE_NONE))
        end
    end

    return nothing
end

# PORT: pl-tabling.c add_newly_created_worklist
# (pl-tabling.c:884-899 at the pin)
"Record `wl` as created by its component, an incomplete table (pl-tabling.c `add_newly_created_worklist`)."
function add_newly_created_worklist(
    ld::PL_local_data{T}, wl::tbl_worklist{T}
)::Nothing where {T}
    c = wl.component::tbl_component{T}
    ld.tabling.incomplete_tables += 1
    wls = c.created_worklists
    if wls === nothing
        r = tbl_alloc(ld, Val(TBL_FREE_WORKLIST_SET))
        wls = r === nothing ? worklist_set{tbl_worklist{T}}() : r
        empty!(wls.members)                         # initBuffer(&wls->members)
        c.created_worklists = wls
    end
    push!(wls.members, wl)

    return nothing
end

# PORT: pl-tabling.c reset_newly_created_worklists
# (pl-tabling.c:901-911 at the pin)
"Drop the created worklists of `c`, freeing them as `flags` says (pl-tabling.c `reset_newly_created_worklists`)."
function reset_newly_created_worklists(
    ld::PL_local_data{T}, c::Union{Nothing, tbl_component{T}}, flags::Int
)::Nothing where {T}
    if c !== nothing
        wls = c.created_worklists
        if wls !== nothing
            c.created_worklists = nothing
            uncount_created_worklists(ld, wls)
            free_worklist_set(ld, wls, flags)
        end
    end

    return nothing
end

# PORT: pl-tabling.c worklist_set_to_array
# (pl-tabling.c:913-922 at the pin)
# DIVERGES: returns the member vector (upstream: the base pointer through `wlp` and the count); empty for none.
"The worklists of `wls`, none for an absent set (pl-tabling.c `worklist_set_to_array`)."
function worklist_set_to_array(
    wls::Union{Nothing, worklist_set{tbl_worklist{T}}}, ::Type{T}
)::Vector{tbl_worklist{T}} where {T}
    wls === nothing && return tbl_worklist{T}[]

    return wls.members
end

# PORT: pl-tabling.c free_worklist_set
# (pl-tabling.c:924-955 at the pin)
# DIVERGES: the reevaluation branch (`atrie->data.IDG->reevaluating`, `reset_reevaluation`) is TB6's: a named refusal;
# `table_is_incomplete` and `destroy_answer_trie` are TB1's (pl-tabling.c:4368, :4472).
"Free the set `wls`; `freewl` (WLFS_*) says which of its worklists are freed or their incomplete tables destroyed (pl-tabling.c `free_worklist_set`)."
function free_worklist_set(
    ld::PL_local_data{T}, wls::worklist_set{tbl_worklist{T}}, freewl::Int
)::Nothing where {T}
    if freewl != 0
        for wl in wls.members
            atrie = wl_table(ld, wl)
            if (freewl & WLFS_FREE_ALL) != 0 || (atrie.flags & TRIE_COMPLETE) != 0
                free_worklist(ld, wl)
            elseif (freewl & WLFS_DISCARD_INCOMPLETE) != 0
                if atrie.IDG !== nothing            # && atrie->data.IDG->reevaluating
                    throw(
                        NotPortedError{T}(
                            mk_sym(T, :reset_reevaluation),
                            "reset_reevaluation (pl-tabling.c:11375)", "TB6"
                        )
                    )
                elseif table_is_incomplete(atrie)
                    destroy_answer_trie(ld, atrie)
                end
            end
        end
    end
    empty!(wls.members)                             # discardBuffer(&wls->members)
    tbl_free(ld, Val(TBL_FREE_WORKLIST_SET), wls)

    return nothing
end

# PORT: pl-tabling.c SINDEX_MAX
# (pl-tabling.c:79 at the pin)
const SINDEX_MAX = 32
# PORT: pl-tabling.c SINDEX_DEPTH
# (pl-tabling.c:80 at the pin: `sizeof(unsigned)`, path levels, a byte each)
const SINDEX_DEPTH = 4
# PORT: pl-tabling.c SINDEX_ARGS
# (pl-tabling.c:81 at the pin: last argument number in a path)
const SINDEX_ARGS = Int(0xff)

# ORIGINAL (TAB1 TB2): upstream's `(unsigned int)index_of_word(*a)` (pl-index.c `index_of_word`) on a dereferenced location:
# the kernel's key of the location (`_index_key_loc`, src/pl-index.jl) cut to its low 32 bits, as upstream's cast does.
"The 32-bit index key of a dereferenced location `(k, w, p)` (pl-index.c `index_of_word`, cast to `unsigned`)."
_sindex_word_key(ld::PL_local_data{T}, k::UInt8, w::word, p::Int) where {T} =
    (_index_key_loc(ld, k, w, p) % UInt32)

# PORT: pl-tabling.c suspension_keys
# (pl-tabling.c:3257-3312 at the pin)
# DIVERGES: the keys are a vector, empty for none (upstream: a malloc'ed array ended by a key with path 0, NULL for none);
# the queue holds the compound WORDS (upstream: their locations, read again by `valueTerm(*queue[qhead])`).
"The index keys of the call-subsumption instance `instance`: breadth first, a key per nonvar argument down to `SINDEX_DEPTH` levels (pl-tabling.c `suspension_keys`)."
function suspension_keys(
    ld::PL_local_data{T}, instance::term_t
)::Vector{sindex_key} where {T}
    k, w, _ = _deref_loc(ld, -(instance + 1))       # p = valTermRef(instance); deRef(p)
    keys = sindex_key[]
    if k == DU_WORD && _is_gcompound(w)             # isTerm(*p)
        queue = word[w]                             # compounds whose arguments are next
        qpath = UInt32[0]
        qlevel = Int[0]
        qhead = 0
        n = 0
        while qhead < length(queue) && n < SINDEX_MAX - 1
            fp = valPtr(queue[qhead + 1])           # Functor f = valueTerm(*queue[qhead])
            path = qpath[qhead + 1]
            level = qlevel[qhead + 1]
            qhead += 1
            arity = arityFunctor(ld.functors, ld.gstack[fp])
            max = level == 0 ? SINDEX_MAX : SINDEX_ARGS
            arity > max && (arity = max)
            i = 0
            while i < arity && n < SINDEX_MAX - 1
                ak, aw, ap = _deref_loc(ld, fp + 1 + i)   # Word a = &f->arguments[i]; deRef(a)
                key = _sindex_word_key(ld, ak, aw, ap)
                if key != 0
                    kpath = path | (UInt32(i + 1) << (8 * level))
                    push!(keys, sindex_key(kpath, key))
                    if ak == DU_WORD && _is_gcompound(aw) && level + 1 < SINDEX_DEPTH
                        push!(queue, aw)
                        push!(qpath, kpath)
                        push!(qlevel, level + 1)
                    end
                    n += 1
                end
                i += 1
            end
        end
    end

    return keys
end

# PORT: pl-tabling.c AK_KEY
# (pl-tabling.c:3319 at the pin: a nonvar there, whose key is returned)
const AK_KEY = 0
# PORT: pl-tabling.c AK_WILD
# (pl-tabling.c:3320 at the pin: a variable there or above: any key)
const AK_WILD = 1
# PORT: pl-tabling.c AK_ABSENT
# (pl-tabling.c:3321 at the pin: a nonvar above it lacks the argument)
const AK_ABSENT = 2

# PORT: pl-tabling.c answer_key
# (pl-tabling.c:3329-3349 at the pin)
# DIVERGES: returns `(how, key)` (upstream: the AK_* code, the key through `*key`).
"How the answer `answer` meets the key path `path` (AK_*) and its key there (pl-tabling.c `answer_key`)."
function answer_key(
    ld::PL_local_data{T}, answer::term_t, path::UInt32
)::Tuple{Int, UInt32} where {T}
    loc = -(answer + 1)                             # Word p = valTermRef(answer)
    while path != 0
        argn = Int(path & 0xff)
        k, w, _ = _deref_loc(ld, loc)
        (k == DU_CELL || k == DU_ATTVAR) && return (AK_WILD, UInt32(0))    # canBind(*p)
        (k == DU_WORD && _is_gcompound(w)) || return (AK_ABSENT, UInt32(0)) # !isTerm(*p)
        fp = valPtr(w)
        argn > arityFunctor(ld.functors, ld.gstack[fp]) && return (AK_ABSENT, UInt32(0))
        loc = fp + argn                             # p = &f->arguments[argn-1]
        path >>= 8
    end
    k, w, p = _deref_loc(ld, loc)
    key = _sindex_word_key(ld, k, w, p)

    return (key != 0 ? AK_KEY : AK_WILD, key)
end

# PORT: pl-tabling.c suspension_matches_index
# (pl-tabling.c:3360-3390 at the pin)
# DIVERGES: `skeys` is indexed by the skeleton's argument number (`skeys[path + 1]`, upstream `skeys[k->path]`, one based).
"False if the instance of `susp` cannot unify with `answer` for a different key at one of its key paths (pl-tabling.c `suspension_matches_index`)."
function suspension_matches_index(
    ld::PL_local_data{T}, susp::suspension{T}, skeys::Vector{sindex_key}, answer::term_t
)::Bool where {T}
    for k in susp.keys                              # likely(susp->keys!=NULL); for(k=susp->keys; k->path; k++)
        if k.path <= SINDEX_ARGS
            ak = skeys[Int(k.path) + 1].key
            (k.key != ak && ak != 0) && return false
        else
            how, ak = answer_key(ld, answer, k.path)
            if how == AK_KEY
                k.key != ak && return false
            elseif how == AK_ABSENT
                return false
            end
        end
    end

    return true
end

# PORT: pl-tabling.c suspension_matches
# (pl-tabling.c:3393-3418 at the pin; the DEBUG print is left out)
"Whether the instance of `susp` unifies with `answer`: 1, 0, or -1 on an exception (pl-tabling.c `suspension_matches`)."
function suspension_matches(
    ld::PL_local_data{T}, answer::term_t, susp::suspension{T}
)::Int where {T}
    inst = susp.instance
    inst === nothing && return -1                   # (a suspension without an instance is never matched upstream)
    fid = PL_open_foreign_frame(ld)
    tmp = PL_new_term_ref(ld)
    if PL_recorded(ld, inst, tmp)
        ok = PL_unify(ld, tmp, answer)
        PL_discard_foreign_frame(ld, fid)
        return ok ? 1 : (PL_exception(ld, 0) != 0 ? -1 : 0)
    end

    return -1
end

# PORT: pl-tabling.c suspension_key_at
# (pl-tabling.c:3424-3436 at the pin)
# DIVERGES: `keys` is a vector, not ended by a key with path 0.
"The key of the suspension `sp` at `path`, 0 for none (pl-tabling.c `suspension_key_at`)."
function suspension_key_at(sp::suspension{T}, path::UInt32)::UInt32 where {T}
    for k in sp.keys
        k.path == path && return k.key
    end

    return UInt32(0)
end

# PORT: pl-tabling.c sindex_free
# (pl-tabling.c:3438-3452 at the pin)
# DIVERGES: the tables and vectors are left to Julia's collector (`destroyHTable`, `free`).
"Drop the index of the suspension cluster `c` (pl-tabling.c `sindex_free`)."
function sindex_free(c::cluster{T})::Nothing where {T}
    c.sindex = nothing

    return nothing
end

# PORT: pl-tabling.c sindex_add
# (pl-tabling.c:3461-3496 at the pin)
# DIVERGES: member numbers are upstream's (from 0, -1 for none), member `i` is at index `i + 1` of `prev` and `prev_all`;
# `allocated` is `length(prev)`; a vector grows or fails with Julia's `OutOfMemoryError`, so the answer is always true.
"Index member `i` (from 0) of a suspension cluster, the member after the last indexed, under the first path it has a key at (pl-tabling.c `sindex_add`)."
function sindex_add(ix::sindex_table, sp::suspension{T}, i::Int)::Bool where {T}
    allocated = length(ix.prev)
    if i >= allocated
        n = allocated != 0 ? allocated * 2 : 16
        while n <= i
            n *= 2
        end
        resize!(ix.prev, n)
        resize!(ix.prev_all, n)
    end

    for j in 1:ix.npaths
        ip = ix.paths[j]
        key = suspension_key_at(sp, ip.path)
        if key != 0
            ix.prev[i + 1] = get(ip.heads, key, 0) - 1  # lookupHTable(ip->heads, key) - 1
            ix.prev_all[i + 1] = ip.all
            ip.heads[key] = i + 1                   # updateHTable(ip->heads, key, i+1)
            ip.all = i
            return true
        end
    end
    ix.prev[i + 1] = ix.unkeyed
    ix.unkeyed = i

    return true
end

# PORT: pl-tabling.c sindex_extend
# (pl-tabling.c:3503-3516 at the pin)
"Index the members of the suspension cluster `c` from `from` (from 0) on, if it has an index (pl-tabling.c `sindex_extend`)."
function sindex_extend(c::cluster{T}, from::Int)::Nothing where {T}
    ix = c.sindex
    if ix !== nothing
        n = length(c.suspensions)
        for i in from:(n - 1)
            if !sindex_add(ix, c.suspensions[i + 1], i)
                sindex_free(c)
                break
            end
        end
    end

    return nothing
end

# PORT: pl-tabling.c init_cluster_index
# (pl-tabling.c:3518-3523 at the pin)
"A cluster without an index (pl-tabling.c `init_cluster_index`)."
function init_cluster_index(c::cluster{T})::Nothing where {T}
    c.sindex = nothing
    c.sindex_tried = 0
    c.paired = false

    return nothing
end

# ORIGINAL (TAB1 TB2): a cluster of `type` for the worklist `wl`: the head of `wl.free_clusters`, else a freed one or a new
# one with no members; the shared head of upstream's `new_answer_cluster` and `new_suspension_cluster` (pl-tabling.c:3529-3537,
# :3637-3645), which are the same lines with another type.
"A cluster of `type` for `wl`, reused when one is free (pl-tabling.c `new_answer_cluster`, `new_suspension_cluster`)."
function _new_cluster(
    ld::PL_local_data{T}, wl::tbl_worklist{T}, type::Int
)::cluster{T} where {T}
    c = wl.free_clusters
    if c !== nothing
        wl.free_clusters = c.next
        c.type = type
    else
        r = tbl_alloc(ld, Val(TBL_FREE_CLUSTER))
        c = r === nothing ? cluster{T}(type) : r
        c.type = type
        empty!(c.answers)                           # initBuffer(&c->members)
        empty!(c.suspensions)
    end
    init_cluster_index(c)

    return c
end

# PORT: pl-tabling.c new_answer_cluster
# (pl-tabling.c:3525-3541 at the pin)
"A new answer cluster of `wl` holding `ans` (pl-tabling.c `new_answer_cluster`)."
function new_answer_cluster(
    ld::PL_local_data{T}, wl::tbl_worklist{T}, ans::answer
)::cluster{T} where {T}
    c = _new_cluster(ld, wl, CLUSTER_ANSWERS)
    push!(c.answers, ans.node)                      # addBuffer(&c->members, *ans, answer)

    return c
end

# PORT: pl-tabling.c free_answer_cluster
# (pl-tabling.c:3543-3547 at the pin)
"Free the answer cluster `c` (pl-tabling.c `free_answer_cluster`)."
function free_answer_cluster(ld::PL_local_data{T}, c::cluster{T})::Nothing where {T}
    empty!(c.answers)                               # discardBuffer(&c->members)
    tbl_free(ld, Val(TBL_FREE_CLUSTER), c)

    return nothing
end

# PORT: pl-tabling.c add_to_answer_cluster
# (pl-tabling.c:3549-3552 at the pin)
"Add `ans` to the answer cluster `c` (pl-tabling.c `add_to_answer_cluster`)."
function add_to_answer_cluster(c::cluster{T}, ans::answer)::Nothing where {T}
    push!(c.answers, ans.node)

    return nothing
end

# PORT: pl-tabling.c merge_answer_clusters
# (pl-tabling.c:3554-3562 at the pin)
"Append the answers of `from` to `to` (pl-tabling.c `merge_answer_clusters`)."
function merge_answer_clusters(to::cluster{T}, from::cluster{T})::Nothing where {T}
    append!(to.answers, from.answers)               # addMultipleBuffer()

    return nothing
end

# PORT: pl-tabling.c get_answer_from_cluster
# (pl-tabling.c:3564-3567 at the pin)
# DIVERGES: the answer by value (upstream: a pointer into the buffer); `index` from 0.
"Answer `index` (from 0) of the answer cluster `c` (pl-tabling.c `get_answer_from_cluster`)."
get_answer_from_cluster(c::cluster{T}, index::Int) where {T} = answer(c.answers[index + 1])

# PORT: pl-tabling.c prune_answer_cluster
# (pl-tabling.c:3569-3586 at the pin)
# DIVERGES: `atrie` is the answer trie the nodes are in (upstream `prune_node(NULL, n)` reaches it through the node; here a
# node is an id in its trie, TR1 `prune_node(gd, tr, nid)`).
"Drop the answers of `c` whose node lost its value, pruning those nodes; the number dropped (pl-tabling.c `prune_answer_cluster`)."
function prune_answer_cluster(
    gd::PL_global_data{T}, atrie::trie{T}, c::cluster{T}
)::Int where {T}
    members = c.answers
    top = length(members)
    out = 0
    for k in 1:top
        n = members[k]
        if atrie.nodes[n].value != 0
            out += 1
            members[out] = n                        # *out++ = *base
        else
            prune_node(gd, atrie, n)
        end
    end
    resize!(members, out)                           # c->members.top = out

    return top - out
end

# PORT: pl-tabling.c IS_TNOT
# (pl-tabling.c:3598-3601 at the pin)
# DIVERGES: the flag is the field `is_tnot` (upstream: bit 0 of the record pointer, set by `TNOT` and cleared by `UNTNOT`,
# pl-tabling.c:3588-3596, which the kernel does not need).
"Whether the suspension `s` is a tnot/1 one (pl-tabling.c `IS_TNOT`)."
IS_TNOT(s::suspension{T}) where {T} = s.is_tnot

# PORT: pl-tabling.c new_suspension
# (pl-tabling.c:3604-3624 at the pin)
# DIVERGES: returns the suspension (upstream fills `*sp`); `instance` 0 is NULL; `PL_record` cannot fail here (no
# resource error: Julia's `OutOfMemoryError`), so neither the `false` answers nor the `PL_erase` of the first record.
"A suspension of the dependency term `term`, with the call-subsumption filter `instance` when not 0 (pl-tabling.c `new_suspension`)."
function new_suspension(
    ld::PL_local_data{T}, term::term_t, is_tnot::Bool, instance::term_t
)::suspension{T} where {T}
    rterm = PL_record(ld, term)
    if instance != 0                                # unlikely(instance)
        rinst = PL_record(ld, instance)
        keys = suspension_keys(ld, instance)
    else
        rinst = nothing
        keys = sindex_key[]                         # sp->keys = NULL
    end

    return suspension{T}(rterm, rinst, keys, is_tnot)  # sp->term = TNOT(sp->term, is_tnot)
end

# PORT: pl-tabling.c new_suspension_cluster
# (pl-tabling.c:3628-3649 at the pin)
# DIVERGES: never `nothing` (as `new_suspension`).
"A new suspension cluster of `wl` holding the suspension of `first` (pl-tabling.c `new_suspension_cluster`)."
function new_suspension_cluster(
    ld::PL_local_data{T}, wl::tbl_worklist{T}, first::term_t, is_tnot::Bool,
    instance::term_t
)::cluster{T} where {T}
    s = new_suspension(ld, first, is_tnot, instance)
    c = _new_cluster(ld, wl, CLUSTER_SUSPENSIONS)
    push!(c.suspensions, s)                         # addBuffer(&c->members, s, suspension)

    return c
end

# PORT: pl-tabling.c free_suspension_cluster
# (pl-tabling.c:3651-3670 at the pin)
"Free the suspension cluster `c`, erasing its records (pl-tabling.c `free_suspension_cluster`)."
function free_suspension_cluster(ld::PL_local_data{T}, c::cluster{T})::Nothing where {T}
    sindex_free(c)
    for s in c.suspensions
        PL_erase(s.term)                            # PL_erase(UNTNOT(s->term))
        inst = s.instance
        inst !== nothing && PL_erase(inst)
    end
    empty!(c.suspensions)                           # discardBuffer(&c->members)
    tbl_free(ld, Val(TBL_FREE_CLUSTER), c)

    return nothing
end

# PORT: pl-tabling.c add_to_suspension_cluster
# (pl-tabling.c:3673-3684 at the pin)
"Add the suspension of `sterm` to the cluster `c` and to its index (pl-tabling.c `add_to_suspension_cluster`)."
function add_to_suspension_cluster(
    ld::PL_local_data{T}, c::cluster{T}, sterm::term_t, is_tnot::Bool, instance::term_t
)::Bool where {T}
    s = new_suspension(ld, sterm, is_tnot, instance)
    push!(c.suspensions, s)
    sindex_extend(c, length(c.suspensions) - 1)

    return true
end

# PORT: pl-tabling.c merge_suspension_cluster
# (pl-tabling.c:3692-3708 at the pin)
# DIVERGES: `PL_free(from)` is left to Julia's collector (the members are emptied).
"Append the suspensions of `from` to `to`, extending the index of `to` and dropping that of `from` (pl-tabling.c `merge_suspension_cluster`)."
function merge_suspension_cluster(
    to::cluster{T}, from::cluster{T}, do_free::Bool
)::Nothing where {T}
    indexed = length(to.suspensions)
    append!(to.suspensions, from.suspensions)       # addMultipleBuffer()
    sindex_extend(to, indexed)
    sindex_free(from)
    init_cluster_index(from)
    do_free && empty!(from.suspensions)             # discardBuffer(&from->members); PL_free(from)

    return nothing
end

# PORT: pl-tabling.c get_suspension_from_cluster
# (pl-tabling.c:3711-3715 at the pin)
# DIVERGES: `index` from 0; the suspension by value.
"Suspension `index` (from 0) of the suspension cluster `c` (pl-tabling.c `get_suspension_from_cluster`)."
get_suspension_from_cluster(c::cluster{T}, index::Int) where {T} = c.suspensions[index + 1]

# PORT: pl-tabling.c free_cluster
# (pl-tabling.c:3717-3723 at the pin)
"Free the cluster `c` by its type (pl-tabling.c `free_cluster`)."
function free_cluster(ld::PL_local_data{T}, c::cluster{T})::Nothing where {T}
    if c.type == CLUSTER_ANSWERS
        free_answer_cluster(ld, c)
    else
        free_suspension_cluster(ld, c)
    end

    return nothing
end

# PORT: pl-tabling.c acp_size
# (pl-tabling.c:3725-3728 at the pin)
"The number of answers of the answer cluster `c` (pl-tabling.c `acp_size`)."
acp_size(c::cluster{T}) where {T} = length(c.answers)

# PORT: pl-tabling.c scp_size
# (pl-tabling.c:3730-3733 at the pin)
"The number of suspensions of the suspension cluster `c` (pl-tabling.c `scp_size`)."
scp_size(c::cluster{T}) where {T} = length(c.suspensions)

# PORT: pl-tabling.c sindex_choose
# (pl-tabling.c:3755-3833 at the pin)
# DIVERGES: the chosen paths are pushed onto the vector `chosen` (upstream: a `tmp_buffer`); the assessments are a vector in the
# order their path was met plus a `Dict` path -> position (upstream: a buffer and a `Table`), so the first best one wins as
# upstream; no allocation fails (Julia's `OutOfMemoryError`).
"Choose greedily the paths to index the suspension cluster `c` on; false if no path saves a visit (pl-tabling.c `sindex_choose`)."
function sindex_choose(c::cluster{T}, chosen::Vector{UInt32})::Bool where {T}
    n = scp_size(c)
    base = c.suspensions
    placed = falses(n)
    where_ = Dict{UInt32, Int}()                    # path -> assessment, plus 1
    as = sindex_assessment[]
    while true                                      # while ( placed )
        best = 0
        most = 1.0
        for i in 1:n
            (placed[i] || isempty(base[i].keys)) && continue
            for k in base[i].keys
                ai = get(where_, k.path, 0)
                if ai == 0
                    push!(as, sindex_assessment(k.path, 0, UInt64(0), Dict{UInt32, Int}()))
                    ai = length(as)
                    where_[k.path] = ai
                end
                a = as[ai]
                count = get(a.counts, k.key, 0)
                a.counts[k.key] = count + 1
                a.squares += UInt64(2 * count + 1)
                a.keyed += 1
            end
        end

        for (j, a) in enumerate(as)
            saved = Float64(a.keyed) - Float64(a.squares) / Float64(a.keyed)
            if saved > most
                most = saved
                best = j
            end
        end
        if best != 0
            path = as[best].path
            push!(chosen, path)
            for i in 1:n
                (!placed[i] && suspension_key_at(base[i], path) != 0) && (placed[i] = true)
            end
        end
        empty!(as)                                  # destroyHTable(a->counts); seekBuffer(&as, 0)
        empty!(where_)                              # clearHTable(where)
        best == 0 && break
    end

    return !isempty(chosen)
end

# PORT: pl-tabling.c scp_index
# (pl-tabling.c:3842-3884 at the pin)
"The index of the suspension cluster `scp` about to meet `answers` answers, or `nothing` to scan it (pl-tabling.c `scp_index`)."
function scp_index(
    ld::PL_local_data{T}, scp::cluster{T}, answers::Int
)::Union{Nothing, sindex_table} where {T}
    again = scp.paired
    n = scp_size(scp)
    scp.paired = true
    ix = scp.sindex
    if ix !== nothing
        n < 2 * ix.built && return ix
        sindex_free(scp)
    end
    (
        n < 2 || (!again && answers < 2) ||
        (scp.sindex_tried != 0 && n < 2 * scp.sindex_tried)
    ) && return nothing
    chosen = UInt32[]
    if !sindex_choose(scp, chosen)
        scp.sindex_tried = n
        return nothing
    end
    npaths = length(chosen)
    paths = sindex_path[sindex_path(chosen[j], Dict{UInt32, Int}(), -1) for j in 1:npaths]
    cursors = sindex_cursor[sindex_cursor(-1, Int[]) for _ in 1:(npaths + 1)]
    scp.sindex = sindex_table(Int[], Int[], -1, n, cursors, npaths, paths)
    sindex_extend(scp, 0)

    return scp.sindex
end

# ---- TB2: the table worklist (pl-tabling.c:3881-4205 at the pin) ----

# ORIGINAL (TAB1 TB2): the memset of a reused worklist (upstream `new_worklist`: `memset(wl, 0, sizeof(*wl))`, then the magic).
"Reset the reused worklist `wl` to a new one (pl-tabling.c `new_worklist`'s memset)."
function _zero_worklist!(wl::tbl_worklist{T})::tbl_worklist{T} where {T}
    wl.head = nothing
    wl.tail = nothing
    wl.riac = nothing
    wl.free_clusters = nothing
    wl.magic = WORKLIST_MAGIC
    wl.ground = false
    wl.executing = false
    wl.in_global_wl = false
    wl.negative = false
    wl.neg_delayed = false
    wl.has_answers = false
    wl.answer_completed = false
    wl.depend_abolish = false
    wl.needs_answer_gc = false
    wl.undefined = 0
    wl.component = nothing
    wl.table = 0
    wl.predicate = nothing
    empty!(wl.delays)                               # initBuffer(&wl->delays)
    empty!(wl.pos_undefined)                        # initBuffer(&wl->pos_undefined)
    wl.ptr = 0

    return wl
end

# PORT: pl-tabling.c new_worklist
# (pl-tabling.c:3884-3899 at the pin)
# DIVERGES: `wl.table` is the trie's number in `gd.tries` (`atrie.serial`, TB1); `atrie.worklist` holds a worklist, NULL
# (`nothing`) or a sentinel (an `Int`, TB1's widening of TR1's field).
"A new worklist for the answer trie `atrie`, which then points at it (pl-tabling.c `new_worklist`)."
function new_worklist(ld::PL_local_data{T}, atrie::trie{T})::tbl_worklist{T} where {T}
    r = tbl_alloc(ld, Val(TBL_FREE_WORKLIST))
    wl = r === nothing ? tbl_worklist{T}() : _zero_worklist!(r)  # memset(wl, 0, sizeof(*wl)); wl->magic = WORKLIST_MAGIC
    wl.table = atrie.serial
    w = atrie.worklist
    (w isa Int && w == WL_GROUND) && (wl.ground = true)
    atrie.worklist = wl

    return wl
end

# PORT: pl-tabling.c free_worklist
# (pl-tabling.c:3902-3929 at the pin)
# DIVERGES: the handle Prolog saw is freed with the worklist (`tbl_pointer_release!`); upstream's "Oops" print for a trie that
# points elsewhere is an `@warn`.
"Free the worklist `wl` and its clusters; its answer trie no longer points at it (pl-tabling.c `free_worklist`)."
function free_worklist(ld::PL_local_data{T}, wl::tbl_worklist{T})::Nothing where {T}
    @assert wl.magic == WORKLIST_MAGIC
    wl.magic = 0

    if wl.table != 0
        atrie = wl_table(ld, wl)
        w = atrie.worklist
        if w !== nothing
            if w === wl
                atrie.worklist = nothing
            else
                @warn "Oops, worklist trie doesn't point back at me!"
            end
        end
    end

    c = wl.head
    while c !== nothing
        next = c.next
        free_cluster(ld, c)
        c = next
    end
    c = wl.free_clusters
    while c !== nothing
        next = c.next
        free_cluster(ld, c)
        c = next
    end
    empty!(wl.delays)                               # discardBuffer(&wl->delays)
    empty!(wl.pos_undefined)                        # discardBuffer(&wl->pos_undefined)

    tbl_pointer_release!(ld, wl)
    tbl_free(ld, Val(TBL_FREE_WORKLIST), wl)

    return nothing
end

# PORT: pl-tabling.c clean_worklist
# (pl-tabling.c:3932-3953 at the pin)
"Free the clusters of `wl`, keeping the worklist (pl-tabling.c `clean_worklist`)."
function clean_worklist(ld::PL_local_data{T}, wl::tbl_worklist{T})::Nothing where {T}
    wl.riac = nothing
    if wl.head !== nothing
        c = wl.head
        while c !== nothing
            next = c.next
            free_cluster(ld, c)
            c = next
        end
        wl.head = nothing
        wl.tail = nothing
    end

    if wl.free_clusters !== nothing
        c = wl.free_clusters
        while c !== nothing
            next = c.next
            free_cluster(ld, c)
            c = next
        end
        wl.free_clusters = nothing
    end

    return nothing
end

# PORT: pl-tabling.c conditional_answer_node
# (pl-tabling.c:3976-3980 at the pin)
# DIVERGES: a node is its id in `atrie`; the answer is the id or 0 (upstream: the node or NULL); `answer_is_conditional`
# (pl-tabling.c:982) is the delays step's (TB4).
"The answer node `n` of `atrie` if it has a value and is conditional, else 0 (pl-tabling.c `conditional_answer_node`)."
function conditional_answer_node(
    ld::PL_local_data{T}, atrie::trie{T}, n::Int
)::Int where {T}
    return if (atrie.nodes[n].value != 0 && answer_is_conditional(_query_gd(ld), atrie, n))
        n
    else
        0
    end
end

# PORT: pl-tabling.c answer_nodes_discardable
# (pl-tabling.c:3983-3995 at the pin)
# DIVERGES: the IDG node (`atrie->data.IDG`) is TB6's: a table with one is refused by name; no table has one before TB6.
"Whether the nodes of the complete answer trie `atrie` may be discarded once it is compiled (pl-tabling.c `answer_nodes_discardable`)."
function answer_nodes_discardable(ld::PL_local_data{T}, atrie::trie{T})::Bool where {T}
    def = atrie.predicate
    atrie.IDG === nothing || throw(
        NotPortedError{T}(
            mk_sym(T, :answer_nodes_discardable),
            "answer_nodes_discardable: an IDG node (monotonic, map_trie_node)",
            "TB6"
        )
    )
    tp = def === nothing ? nothing : def.tabling

    return (atrie.flags & (TRIE_ISMAP | TRIE_ISSHARED | TRIE_ISTRACKED)) == 0 &&   # !(idg && idg->monotonic)
           tp !== nothing &&
           (tp.flags & TP_VARIANT) != 0 &&
           (tp.flags & TP_MONOTONIC) == 0                                           # !(idg && map_trie_node(...))
end

# PORT: pl-tabling.c complete_worklist
# (pl-tabling.c:3997-4020 at the pin; COMPLETE_WORKLIST without O_PLMT: the code alone, pl-tabling.c:383)
# DIVERGES: `tt_has_modified_dependencies` (an IDG node, pl-tabling.c:7416) is TB6's: a table with an IDG node is refused by
# name; without one it is false.
"Complete the worklist `wl`: freed when `destroy`, else kept without clusters; its answer trie is complete (pl-tabling.c `complete_worklist`)."
function complete_worklist(
    ld::PL_local_data{T}, wl::tbl_worklist{T}, destroy::Bool
)::Nothing where {T}
    atrie = wl_table(ld, wl)

    atrie.IDG === nothing || throw(
        NotPortedError{T}(
            mk_sym(T, :tt_has_modified_dependencies),
            "tt_has_modified_dependencies (pl-tabling.c:7416)",
            "TB6"
        )
    )

    if destroy
        free_worklist(ld, wl)
        atrie.worklist = nothing
        answer_nodes_discardable(ld, atrie) && (atrie.flags |= TRIE_DISCARDABLE)
        atrie.flags |= TRIE_COMPLETE
    else
        clean_worklist(ld, wl)
        wl.component = nothing                      # (*)
        atrie.flags |= TRIE_COMPLETE
    end

    return nothing
end

# PORT: pl-tabling.c worklist_negative
# (pl-tabling.c:4023-4033 at the pin)
"Mark `wl` a suspended negation, on its component's delay worklists (pl-tabling.c `worklist_negative`)."
function worklist_negative(ld::PL_local_data{T}, wl::tbl_worklist{T})::Bool where {T}
    if !wl.negative
        wl.negative = true
        add_delay_worklist(ld, wl)
        c = wl.component::tbl_component{T}
        c.neg_status == SCC_NEG_NONE && (c.neg_status = SCC_NEG_DELAY)
    end

    return true
end

# PORT: pl-tabling.c prune_answers_worklist
# (pl-tabling.c:4048-4061 at the pin; the DEBUG print is left out)
"Drop the deleted answers from the answer clusters of `wl`; the number dropped (pl-tabling.c `prune_answers_worklist`)."
function prune_answers_worklist(ld::PL_local_data{T}, wl::tbl_worklist{T})::Int where {T}
    gd = _query_gd(ld)
    atrie = wl_table(ld, wl)
    gained = 0
    c = wl.head
    while c !== nothing
        c.type == CLUSTER_ANSWERS && (gained += prune_answer_cluster(gd, atrie, c))
        c = c.next
    end

    return gained
end

# PORT: pl-tabling.c worklist_work_done
# (pl-tabling.c:4069-4072 at the pin)
"Whether `wl` has no answer cluster or no suspension right of it (pl-tabling.c `worklist_work_done`)."
worklist_work_done(wl::tbl_worklist{T}) where {T} =
    (riac=wl.riac; riac === nothing || riac.next === nothing)

# PORT: pl-tabling.c wkl_append_left
# (pl-tabling.c:4075-4086 at the pin)
"Put the cluster `c` at the head of `wl` (pl-tabling.c `wkl_append_left`)."
function wkl_append_left(wl::tbl_worklist{T}, c::cluster{T})::Nothing where {T}
    h = wl.head
    if h !== nothing
        c.prev = nothing
        c.next = h
        h.prev = c
        wl.head = c
    else
        c.next = nothing
        c.prev = nothing
        wl.head = c
        wl.tail = c
    end

    return nothing
end

# PORT: pl-tabling.c wkl_append_right
# (pl-tabling.c:4089-4100 at the pin)
"Put the cluster `c` at the tail of `wl` (pl-tabling.c `wkl_append_right`)."
function wkl_append_right(wl::tbl_worklist{T}, c::cluster{T})::Nothing where {T}
    t = wl.tail
    if t !== nothing
        c.next = nothing
        c.prev = t
        t.next = c
        wl.tail = c
    else
        c.next = nothing
        c.prev = nothing
        wl.head = c
        wl.tail = c
    end

    return nothing
end

# PORT: pl-tabling.c update_riac
# (pl-tabling.c:4103-4118 at the pin)
"After moving the answer cluster `acp` right, set the rightmost inner answer cluster of `wl` (pl-tabling.c `update_riac`)."
function update_riac(wl::tbl_worklist{T}, acp::cluster{T})::Nothing where {T}
    nx = acp.next
    if nx === nothing || nx.type == CLUSTER_ANSWERS
        c = acp.prev
        while c !== nothing
            if c.type == CLUSTER_ANSWERS
                wl.riac = c
                return nothing
            end
            c = c.prev
        end

        wl.riac = nothing
    end

    return nothing
end

# PORT: pl-tabling.c wkl_swap_clusters
# (pl-tabling.c:4121-4138 at the pin; the DEBUG print is left out)
"Swap the answer cluster `acp` with the suspension cluster `scp` right of it in `wl` (pl-tabling.c `wkl_swap_clusters`)."
function wkl_swap_clusters(
    wl::tbl_worklist{T}, acp::cluster{T}, scp::cluster{T}
)::Nothing where {T}
    a = acp.prev                                    # before the couple
    z = scp.next                                    # after the couple

    @assert acp.next === scp

    if a !== nothing
        a.next = scp
    else
        wl.head = scp
    end
    if z !== nothing
        z.prev = acp
    else
        wl.tail = acp
    end
    scp.prev = a
    acp.next = z
    scp.next = acp
    acp.prev = scp

    update_riac(wl, acp)

    return nothing
end

# PORT: pl-tabling.c potentially_add_to_global_worklist
# (pl-tabling.c:4141-4146 at the pin)
"Schedule `wl` unless it is scheduled or executing (pl-tabling.c `potentially_add_to_global_worklist`)."
function potentially_add_to_global_worklist(
    ld::PL_local_data{T}, wl::tbl_worklist{T}
)::Nothing where {T}
    (!wl.in_global_wl && !wl.executing) && add_global_worklist(ld, wl)

    return nothing
end

# PORT: pl-tabling.c wkl_add_answer
# (pl-tabling.c:4149-4170 at the pin; the DEBUG print is left out)
# DIVERGES: `an` is the answer's node id in the answer trie of `wl`; `answer_is_conditional` is TB4's (pl-tabling.c:982).
"Add the answer node `an` to `wl`, scheduling it (pl-tabling.c `wkl_add_answer`)."
function wkl_add_answer(ld::PL_local_data{T}, wl::tbl_worklist{T}, an::Int)::Bool where {T}
    potentially_add_to_global_worklist(ld, wl)
    ans = answer(an)

    answer_is_conditional(_query_gd(ld), wl_table(ld, wl), an) || (wl.has_answers = true)

    h = wl.head
    if h !== nothing && h.type == CLUSTER_ANSWERS
        add_to_answer_cluster(h, ans)
    else
        c = new_answer_cluster(ld, wl, ans)
        wkl_append_left(wl, c)
        wl.riac === nothing && (wl.riac = c)
    end

    return true
end

# PORT: pl-tabling.c wkl_add_suspension
# (pl-tabling.c:4173-4193 at the pin; the DEBUG print is left out)
"Add the suspension `suspension` (a tnot/1 one when `is_tnot`, filtered by `inst` when not 0) to `wl`, scheduling it (pl-tabling.c `wkl_add_suspension`)."
function wkl_add_suspension(
    ld::PL_local_data{T}, wl::tbl_worklist{T}, suspension::term_t, is_tnot::Bool,
    inst::term_t
)::Bool where {T}
    potentially_add_to_global_worklist(ld, wl)
    t = wl.tail
    if t !== nothing && t.type == CLUSTER_SUSPENSIONS
        add_to_suspension_cluster(ld, t, suspension, is_tnot, inst) || return false
    else
        c = new_suspension_cluster(ld, wl, suspension, is_tnot, inst)
        wkl_append_right(wl, c)
        p = c.prev
        (p !== nothing && p.type == CLUSTER_ANSWERS) && (wl.riac = p)
    end

    return true
end

# PORT: pl-tabling.c tripwire_incomplete_subgoals
# (pl-tabling.c:11943-11954 at the pin.)
# DIVERGES: the tripwire itself (`tbl_pred_tripwire`, the restraint action) is a named refusal, owner TB8; the limit is -1 (none)
# until TB8 sets the restraint.
"False after a tripwire raised for the limit `max_incomplete_subgoals` of `def`; true to go on (pl-tabling.c)."
function tripwire_incomplete_subgoals(
    ld::PL_local_data{T}, def::Union{Nothing, Definition{T}}
)::Bool where {T}
    limit = ld.tabling.restraint.max_incomplete_subgoals
    if limit != -1 && def !== nothing && ld.tabling.incomplete_tables == limit
        tbl_refuse(
            T,
            :tbl_pred_tripwire,
            "tripwire_incomplete_subgoals: max_incomplete_subgoals reached (tbl_pred_tripwire)",
            "TB8"
        )
    end

    return true
end

# PORT: pl-tabling.c tripwire_scc_subgoals
# (pl-tabling.c:11956-11965 at the pin.)
# DIVERGES: the tripwire itself (`tbl_wl_tripwire`) is a named refusal, owner TB8; the limit is -1 (none) until TB8.
"False after a tripwire raised for the limit `max_scc_subgoals` of the component of `wl` (`size0`: its size before the merge); true to go on (pl-tabling.c)."
function tripwire_scc_subgoals(
    ld::PL_local_data{T}, wl::tbl_worklist{T}, size0::Int
)::Bool where {T}
    limit = ld.tabling.restraint.max_scc_subgoals
    if limit != -1 && size0 <= limit &&
        wls_size((wl.component::tbl_component{T}).created_worklists) > limit
        tbl_refuse(
            T,
            :tbl_wl_tripwire,
            "tripwire_scc_subgoals: max_scc_subgoals reached (tbl_wl_tripwire)",
            "TB8"
        )
    end

    return true
end

# The `create` branch of unify_fresh (pl-tabling.c:4219-4259 at the pin; TB1 ports the function and its `create` false branch)
# DIVERGES: the two pointers are handles (`tbl_pointer!`), so upstream's fast path that builds `fresh(SCC, WL)` from two tagged
# integers on the global stack and its `PL_unify_term` fallback are one unification; `tripwire_incomplete_subgoals`
# (pl-tabling.c:11943) is above. TB1's `unify_fresh` calls it for `create`.
"The `create` branch of `unify_fresh`: a component and a worklist for the new table `atrie`, `t` unified with `fresh(SCC, WL)` (pl-tabling.c)."
function _unify_fresh_create(
    ld::PL_local_data{T}, t::term_t, atrie::trie{T}, def::Union{Nothing, Definition{T}}
)::Bool where {T}
    tripwire_incomplete_subgoals(ld, def) || return false

    scc = tbl_create_subcomponent(ld, atrie)
    wl = tbl_add_worklist(ld, atrie, scc)

    fname = (atrie.flags & TRIE_ISSHARED) != 0 ? :fresh_shared : :fresh
    wl.predicate = def
    PL_unify_functor(ld, t, mk_sym(T, fname), 2) || return false
    a = PL_new_term_ref(ld)
    _PL_get_arg(ld, 1, t, a)
    tbl_unify_pointer(ld, a, scc) || return false
    _PL_get_arg(ld, 2, t, a)

    return tbl_unify_pointer(ld, a, wl)
end

# PORT: pl-tabling.c get_scc
# (pl-tabling.c:4392-4407 at the pin)
# DIVERGES: the handle is read by `tbl_get_pointer`: no integer is `PL_get_pointer_ex`'s type_error(address, T); an integer
# that names no live component (upstream: its magic differs) is the existence error. The component is returned, `nothing`
# with the error raised (upstream: `*cp` and the truth value).
"The component whose handle is `t`, or `nothing` after raising the error (pl-tabling.c `get_scc`)."
function get_scc(
    ld::PL_local_data{T}, t::term_t
)::Union{Nothing, tbl_component{T}} where {T}
    if PL_get_int64(ld, t) === nothing              # PL_get_pointer_ex(t, &ptr)
        PL_error(ld, ERR_TYPE, mk_sym(T, :address), t)
        return nothing
    end
    c = tbl_get_pointer(ld, t)
    if !(c isa tbl_component{T}) || c.magic != COMPONENT_MAGIC
        PL_error(ld, ERR_EXISTENCE, mk_sym(T, Symbol("table component")), t)
        return nothing
    end

    return c
end

# PORT: pl-tabling.c get_worklist
# (pl-tabling.c:4409-4422 at the pin)
# DIVERGES: a handle that names no live worklist (upstream: `assert(wl->magic == WORKLIST_MAGIC)` on the address) raises
# type_error(worklist, T) as a non-integer does.
"The worklist whose handle is `t`, or `nothing` after raising type_error(worklist, T) (pl-tabling.c `get_worklist`)."
function get_worklist(
    ld::PL_local_data{T}, t::term_t
)::Union{Nothing, tbl_worklist{T}} where {T}
    wl = tbl_get_pointer(ld, t)
    if wl isa tbl_worklist{T} && wl.magic == WORKLIST_MAGIC
        return wl
    end
    PL_type_error(ld, "worklist", t)

    return nothing
end

# PORT: pl-tabling.c tnot_get_worklist
# (pl-tabling.c:4425-4453 at the pin)
# DIVERGES: returns `(wl, is_tnot)`, `wl` `nothing` after raising type_error(worklist, T); a handle that names no live worklist
# is that error (upstream: an assert).
"The worklist of `t`, a handle or `tnot(Handle)`, and whether it is the tnot/1 form (pl-tabling.c `tnot_get_worklist`)."
function tnot_get_worklist(
    ld::PL_local_data{T}, t::term_t
)::Tuple{Union{Nothing, tbl_worklist{T}}, Bool} where {T}
    wl = tbl_get_pointer(ld, t)
    (wl isa tbl_worklist{T} && wl.magic == WORKLIST_MAGIC) && return (wl, false)

    if PL_is_functor(ld, t, mk_sym(T, :tnot), 1)
        a = PL_new_term_ref(ld)
        _PL_get_arg(ld, 1, t, a)
        wl = tbl_get_pointer(ld, a)
        (wl isa tbl_worklist{T} && wl.magic == WORKLIST_MAGIC) && return (wl, true)
    end
    PL_type_error(ld, "worklist", t)

    return (nothing, false)
end

# PORT: pl-tabling.c tbl_add_worklist
# (pl-tabling.c:4455-4469 at the pin)
# DIVERGES: `WL_IS_WORKLIST(atrie->data.worklist)` is `atrie.worklist isa tbl_worklist{T}` (the field holds a worklist, NULL
# or a sentinel `Int`).
"The worklist of `atrie` (made when it has none) in the component `scc`, scheduled and created there; the table is incomplete (pl-tabling.c `tbl_add_worklist`)."
function tbl_add_worklist(
    ld::PL_local_data{T}, atrie::trie{T}, scc::tbl_component{T}
)::tbl_worklist{T} where {T}
    w = atrie.worklist
    wl = w isa tbl_worklist{T} ? w : new_worklist(ld, atrie)

    wl.component = scc
    add_global_worklist(ld, wl)
    add_newly_created_worklist(ld, wl)
    atrie.flags &= ~TRIE_COMPLETE

    return wl
end

# PORT: pl-tabling.c frame_worklist
# (pl-tabling.c:4914-4931 at the pin)
# DIVERGES: `fr` is the frame's index in `ld.frames`; the handle in argument 4 is read by `get_worklist` alone (upstream: a
# tagged integer cast to the address, `get_worklist` otherwise; both are a handle here).
"The worklist of argument 4 of the `'\$tbl_reset'/6` frame `fr`, or `nothing` after raising the error (pl-tabling.c `frame_worklist`)."
function frame_worklist(
    ld::PL_local_data{T}, fr::Int
)::Union{Nothing, tbl_worklist{T}} where {T}
    return get_worklist(ld, argFrameP(ld.frames[fr].base, 3))
end

# PORT: pl-tabling.c tbl_reset_add_answer
# (pl-tabling.c:4933-4975 at the pin; the O_PLMT assertion is left out)
# DIVERGES: `fr` is the frame's index in `ld.frames`, which does not move when the foreign frame is opened (upstream reads it
# again through `consTermRef(fr)`); a node is its id; `tbl_add_answer`, `tbl_add_answer_found` and `TBL_ANSWER_COMPLETE`
# (pl-tabling.c:4750-4800) are the answers step's (TB3), `answer_is_conditional` (:982) the delays step's (TB4).
"Add the answer in arguments 5 and 6 of the `'\$tbl_reset'/6` frame `fr` to its worklist; true if that completes the table (pl-tabling.c `tbl_reset_add_answer`)."
function tbl_reset_add_answer(ld::PL_local_data{T}, fr::Int)::Bool where {T}
    wl = frame_worklist(ld, fr)
    wl === nothing && return false
    atrie = wl_table(ld, wl)
    base = ld.frames[fr].base

    if (atrie.flags & TRIE_ISMAP) == 0
        rc, node = trie_insert_flat(ld, atrie, -(argFrameP(base, 4) + 1))
        if rc == 1 &&
            atrie.nodes[node].value == ATOM_trienode &&
            (atrie.nodes[node].flags & TN_IDG_DELETED) == 0 &&
            !answer_is_conditional(_query_gd(ld), atrie, node)
            return false                            # variant of an existing answer
        end
    else
        rc = 0                                      # not used
        node = 0
    end

    fid = PL_open_foreign_frame(ld)
    rcadd = if (atrie.flags & TRIE_ISMAP) != 0
        tbl_add_answer(ld, wl, argFrameP(base, 4), argFrameP(base, 5))
    else
        tbl_add_answer_found(ld, wl, argFrameP(base, 4), argFrameP(base, 5), rc, node)
    end
    PL_close_foreign_frame(ld, fid)

    return rcadd == TBL_ANSWER_COMPLETE
end

# ---- TB2b: the worklist predicates and '$tbl_wkl_work'/6 (pl-tabling.c:5260-6022 at the pin) ----

# PORT: pl-tabling.c tbl_pop_worklist as pl_tbl_pop_worklist2_va
# (pl-tabling.c:4686-4715 at the pin: PRED_IMPL("$tbl_pop_worklist", 2, tbl_pop_worklist, 0))
# `O_AC_EAGER` is defined at the pin (pl-tabling.c:71), so the `scc->simplifications ||` test under `#ifndef O_AC_EAGER`
# is left out as upstream's preprocessor leaves it out.
"`'\$tbl_pop_worklist'(+SCC, -Worklist)`: pop the next worklist of the active component `SCC`, a negative one when no other is left (pl-tabling.c)."
function pl_tbl_pop_worklist2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    scc = get_scc(ld, A1)

    if scc !== nothing
        if scc.status == SCC_ACTIVE
            wl = pop_worklist(ld, scc)
            wl !== nothing && return tbl_unify_pointer(ld, A2, wl) ? FTRUE : FFALSE

            if scc.neg_status != SCC_NEG_NONE
                wl = negative_worklist(ld, scc)
                wl !== nothing && return tbl_unify_pointer(ld, A2, wl) ? FTRUE : FFALSE
            end
        end
    end

    return FFALSE
end

# PORT: pl-tabling.c tbl_wkl_add_suspension as pl_tbl_wkl_add_suspension2_va
# (pl-tabling.c:5265-5276 at the pin: PRED_IMPL("$tbl_wkl_add_suspension", 2, tbl_wkl_add_suspension, 0))
"`'\$tbl_wkl_add_suspension'(+Worklist, +Suspension)`: add `Suspension` to the worklist (pl-tabling.c)."
function pl_tbl_wkl_add_suspension2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    wl, is_tnot = tnot_get_worklist(ld, A1)
    wl !== nothing && return wkl_add_suspension(ld, wl, A2, is_tnot, 0) ? FTRUE : FFALSE

    return FFALSE
end

# PORT: pl-tabling.c tbl_wkl_add_suspension as pl_tbl_wkl_add_suspension3_va
# (pl-tabling.c:5283-5294 at the pin: PRED_IMPL("$tbl_wkl_add_suspension", 3, tbl_wkl_add_suspension, 0))
"`'\$tbl_wkl_add_suspension'(+Worklist, +Instance, +Suspension)`: add `Suspension`, which takes only the answers that unify with `Instance` (call subsumption) (pl-tabling.c)."
function pl_tbl_wkl_add_suspension3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    wl, is_tnot = tnot_get_worklist(ld, A1)
    wl !== nothing && return wkl_add_suspension(ld, wl, A3, is_tnot, A2) ? FTRUE : FFALSE

    return FFALSE
end

# PORT: pl-tabling.c tbl_wkl_make_follower as pl_tbl_wkl_make_follower1_va
# (pl-tabling.c:5305-5353 at the pin: PRED_IMPL("$tbl_wkl_make_follower", 1, tbl_wkl_make_follower, 0))
"`'\$tbl_wkl_make_follower'(+Worklist)`: a former leader merged into a parent component; its answer clusters move in front of its suspension clusters (pl-tabling.c)."
function pl_tbl_wkl_make_follower1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    wl = get_worklist(ld, A1)
    if wl !== nothing
        scp = nothing
        acp = nothing

        c = wl.head
        while c !== nothing
            next = c.next

            if c.type == CLUSTER_ANSWERS
                if acp !== nothing
                    merge_answer_clusters(acp, c)
                    free_answer_cluster(ld, c)
                else
                    acp = c
                    acp.prev = acp.next = nothing
                end
            else
                if scp !== nothing
                    merge_suspension_cluster(scp, c, true)
                else
                    scp = c
                    scp.prev = scp.next = nothing
                end
            end
            c = next
        end

        wl.head = wl.tail = nothing
        if acp !== nothing
            wkl_append_left(wl, acp)
            wl.riac = acp
        else
            wl.riac = nothing
        end
        scp !== nothing && wkl_append_right(wl, scp)

        (acp !== nothing && scp !== nothing) && add_global_worklist(ld, wl)

        return FTRUE
    end

    return FFALSE
end

# PORT: pl-tabling.c tbl_wkl_done as pl_tbl_wkl_done1_va
# (pl-tabling.c:5361-5367 at the pin: PRED_IMPL("$tbl_wkl_done", 1, tbl_wkl_done, 0))
"`'\$tbl_wkl_done'(+Worklist)`: true if the worklist has no work left (pl-tabling.c)."
function pl_tbl_wkl_done1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    wl = get_worklist(ld, A1)

    return (wl !== nothing && worklist_work_done(wl)) ? FTRUE : FFALSE
end

# PORT: pl-tabling.c tbl_wkl_answer_trie as pl_tbl_wkl_answer_trie2_va
# (pl-tabling.c:5412-5419 at the pin: PRED_IMPL("$tbl_wkl_answer_trie", 2, tbl_wkl_answer_trie, 0))
# DIVERGES: the trie's symbol is unified by TR1's `unify_trie` (upstream: `PL_unify_atom(A2, trie_symbol(wl->table))`).
"`'\$tbl_wkl_answer_trie'(+Worklist, -Trie)`: `Trie` is the answer trie of the worklist (pl-tabling.c)."
function pl_tbl_wkl_answer_trie2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    wl = get_worklist(ld, A1)

    return if (wl !== nothing && unify_trie(_query_gd(ld), ld, A2, wl_table(ld, wl)))
        FTRUE
    else
        FFALSE
    end
end

# ORIGINAL (TAB1 TB2): `tbl_unify_answer` (pl-tabling.c:5461), `unify_dependency` (:5480) and `idg_set_current_wl` (:8512),
# which `'$tbl_wkl_work'/6` calls, are the answers step's (TB3, wip/tb3), with the signatures
# `tbl_unify_answer(ld, atrie::trie{T}, node::Int, term::term_t)::Bool` and
# `unify_dependency(ld, a0::term_t, dependency::term_t, wl::tbl_worklist{T}, answer::Int, unified::Bool)::Bool`.

# PORT: pl-tabling.c sindex_candidates
# (pl-tabling.c:5573-5605 at the pin)
# DIVERGES: a cursor's `link` is the vector `ix.prev` or `ix.prev_all` itself, empty for NULL; `heads` holds member + 1, 0 for
# none, so `get(..., 0) - 1` is upstream's `lookupHTable(...) - 1`.
"Point the cursors of `ix` at the candidates of the answer `answer`; the first candidate, the highest member a cursor is at, or -1 (pl-tabling.c `sindex_candidates`)."
function sindex_candidates(
    ld::PL_local_data{T}, ix::sindex_table, answer::term_t
)::Int where {T}
    first = ix.unkeyed

    for j in 1:ix.npaths
        c = ix.cursors[j]
        ip = ix.paths[j]
        how, key = answer_key(ld, answer, ip.path)
        if how == AK_KEY
            c.at = get(ip.heads, key, 0) - 1
            c.link = ix.prev
        elseif how == AK_WILD
            c.at = ip.all
            c.link = ix.prev_all
        else
            c.at = -1
            c.link = Int[]
        end
        c.at > first && (first = c.at)
    end
    c = ix.cursors[ix.npaths + 1]
    c.at = ix.unkeyed
    c.link = ix.prev

    return first
end

# PORT: pl-tabling.c sindex_next
# (pl-tabling.c:5612-5626 at the pin)
"Move the cursor at member `i` down its chain; the next candidate, the highest member a cursor is at, or -1 (pl-tabling.c `sindex_next`)."
function sindex_next(ix::sindex_table, i::Int)::Int
    next = -1

    for j in 1:(ix.npaths + 1)
        c = ix.cursors[j]
        c.at == i && (c.at = c.link[i + 1])
        c.at > next && (next = c.at)
    end

    return next
end

# PORT: pl-tabling.c wkl_next_suspension
# (pl-tabling.c:5632-5647 at the pin)
"Move `state` to the next suspension to offer the current answer: the next keyed candidate, else the next one down; false when exhausted (pl-tabling.c `wkl_next_suspension`)."
function wkl_next_suspension(state::wkl_step_state{T})::Bool where {T}
    if state.candidates == CAND_KEYED
        i = sindex_next(state.sindex::sindex_table, state.here)
        if i >= 0
            state.here = i
            return true
        end
        state.candidates = CAND_ALL
        state.here = 0                              # state->suspensions.here = state->suspensions.base
    end
    state.here -= 1

    return state.here >= 0
end

# PORT: pl-tabling.c advance_wkl_state
# (pl-tabling.c:5650-5712 at the pin; the DEBUG print is left out)
# DIVERGES: upstream's `goto next` is the loop's `continue`, its `goto next_answer` (a jump into the else branch) the loop's
# `break` to the lines after it; a cluster put on `free_clusters` is emptied by `empty!` (upstream: `seekBuffer(&c->members,
# 0, ...)`).
"Advance `state` to the next (answer, suspension) pair, moving to the next cluster pair of its worklist when one is exhausted; false when no work is left (pl-tabling.c `advance_wkl_state`)."
function advance_wkl_state(ld::PL_local_data{T}, state::wkl_step_state{T})::Bool where {T}
    while true                                      # next:
        wkl_next_suspension(state) && return true
        state.here = state.top
        state.acp_index -= 1
        state.acp_index != 0 && break               # else { next_answer: ... }

        list = state.list::tbl_worklist{T}

        # Merge adjacent suspension clusters
        scp = state.scp::cluster{T}
        sprev = scp.prev
        if sprev !== nothing && sprev.type == CLUSTER_SUSPENSIONS
            sprev.next = scp.next
            (scp.next::cluster{T}).prev = sprev
            merge_suspension_cluster(sprev, scp, false)
            empty!(scp.suspensions)                 # seekBuffer(&scp->members, 0, record_t)
            scp.next = list.free_clusters
            list.free_clusters = scp
        end
        state.sindex = nothing

        # Merge adjacent answer clusters
        acp = state.acp::cluster{T}
        anext = acp.next
        if anext !== nothing && anext.type == CLUSTER_ANSWERS
            (acp.prev::cluster{T}).next = anext
            anext.prev = acp.prev
            merge_answer_clusters(anext, acp)
            empty!(acp.answers)                     # seekBuffer(&acp->members, 0, answer)
            acp.next = list.free_clusters
            list.free_clusters = acp
        end

        # If more work, re-initialize
        racp = list.riac
        rscp = racp === nothing ? nothing : racp.next
        if racp !== nothing && rscp !== nothing
            @assert racp.type == CLUSTER_ANSWERS
            @assert rscp.type == CLUSTER_SUSPENSIONS
            wkl_swap_clusters(list, racp, rscp)
            state.acp = racp
            state.scp = rscp
            state.acp_index = acp_size(racp)

            if state.acp_index > 0 && scp_size(rscp) > 0
                state.top = scp_size(rscp) - 1
                state.here = state.top
                state.sindex = scp_index(ld, rscp, state.acp_index)
                break                               # goto next_answer
            else
                continue                            # goto next
            end
        end

        return false
    end
    # next_answer:
    state.answer = get_answer_from_cluster(state.acp::cluster{T}, state.acp_index - 1).node
    state.keys_inited = false
    state.candidates = CAND_UNDECIDED

    return true
end

# PORT: pl-tabling.c free_wkl_state
# (pl-tabling.c:5715-5723 at the pin)
# DIVERGES: `i` is the state's index in `ld.tabling.wkl_states` (upstream: the state, `freeForeignState`).
"End the enumeration of the state at `i`: the worklist is no longer executing, its garbage answers are pruned (pl-tabling.c `free_wkl_state`)."
function free_wkl_state(ld::PL_local_data{T}, i::Int)::Nothing where {T}
    pool = ld.tabling.wkl_states
    state = pool.states[i]
    wl = state.list::tbl_worklist{T}

    wl.executing = false
    state.list = state.acp = state.scp = nothing
    state.sindex = nothing
    free_foreign_state!(pool, i)                    # freeForeignState(state, sizeof(*state))
    wl.needs_answer_gc && prune_answers_worklist(ld, wl)

    return nothing
end

# PORT: pl-tabling.c tbl_wkl_work as pl_tbl_wkl_work6_va
# (pl-tabling.c:5735-6022 at the pin: PRED_IMPL("$tbl_wkl_work", 6, tbl_wkl_work, PL_FA_NONDETERMINISTIC); DEBUG prints left out)
# DIVERGES: the state is a record of `ld.tabling.wkl_states`, its index the REDO_PTR context (`PL_retry_address`); the mark
# is a local `Mark(ld)` (upstream: `Mark(fli_context->mark)`), undone by `Undo!`; an answer is its node id in the answer trie
# of the worklist (0: the NULL node of the negative dummy); the argument keys are read off the dereferenced arguments
# (`_deref_loc`, as `indexOfWord` follows a reference); `UNTNOT(sp->term)` is `sp.term`, `IS_TNOT` `sp.is_tnot`;
# `LD->attvar.attvars` is `ld.attvar_attvars`.
"`'\$tbl_wkl_work'(+Worklist, -Answer, -Continuation, -TargetSkeleton, -TargetWorklist, -Delays)`: the next answer to try on a suspension of the worklist, nondeterministic (pl-tabling.c)."
function pl_tbl_wkl_work6_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    pool = ld.tabling.wkl_states
    can = 0                                         # trie_node *can = NULL

    ctl = PL_foreign_control(PL__ctx)
    if ctl == FRG_FIRST_CALL
        wl = get_worklist(ld, A1)
        wl === nothing && return FFALSE
        acp = wl.riac
        acp === nothing && return FFALSE
        scp = acp.next
        scp === nothing && return FFALSE            # if ( !(acp = wl->riac) || !(scp = acp->next) ) fail
        sz_acp = acp_size(acp)
        sz_scp = scp_size(scp)

        wkl_swap_clusters(wl, acp, scp)

        (sz_acp > 0 && sz_scp > 0) || return FFALSE
        idx = alloc_foreign_state!(pool)            # state = allocForeignState(sizeof(*state))
        state = pool.states[idx]
        state.list = wl
        state.acp = acp
        state.scp = scp
        state.acp_index = sz_acp
        state.answer = get_answer_from_cluster(acp, sz_acp - 1).node
        state.top = sz_scp - 1                      # state->suspensions.base = member 0
        state.here = state.top
        state.keys_inited = false
        length(state.keys) == SINDEX_MAX + 1 || resize!(state.keys, SINDEX_MAX + 1)
        state.sindex = scp_index(ld, scp, sz_acp)
        state.candidates = CAND_UNDECIDED
        wl.executing = true
    elseif ctl == FRG_REDO
        idx = PL_foreign_context_address(PL__ctx)   # state = CTX_PTR
        state = pool.states[idx]
    else                                            # FRG_CUTTED
        free_wkl_state(ld, PL_foreign_context_address(PL__ctx))
        return FTRUE
    end

    m = Mark(ld)                                    # Mark(fli_context->mark)
    atrie = wl_table(ld, state.list::tbl_worklist{T})

    while true                                      # do { ... } while ( advance_wkl_state(state) )
        an = state.answer
        scp = state.scp::cluster{T}

        # Ignore (1) removed answer due to simplification, (2) dummy restart for delayed negation,
        # (3) conditional answer for tnot
        if an != 0 && atrie.nodes[an].value == 0   # removed answer
            state.here = 0                          # skip all suspensions
            state.candidates = CAND_ALL
            @goto next
        end

        # An indexed suspension cluster offers a new answer only to its candidates, from the top down as the scan does.
        if state.candidates == CAND_UNDECIDED
            state.candidates = CAND_ALL
            if state.sindex !== nothing && an != 0
                if can != an
                    can != 0 && Undo!(ld, m)
                    tbl_unify_answer(ld, atrie, an, A2) || @goto out_fail   # resource error
                    can = an
                end
                i = sindex_candidates(ld, state.sindex::sindex_table, A2)
                if i < 0
                    state.here = 0                  # none
                    @goto next
                end
                state.here = i
                state.candidates = CAND_KEYED
            end
        end

        sp = get_suspension_from_cluster(scp, state.here)

        if (an == 0 && !sp.is_tnot) ||
            (an != 0 && sp.is_tnot && answer_is_conditional(_query_gd(ld), atrie, an))
            @goto next
        end

        # Call subsumption: filter out suspensions for which the answer does not unify with the answer skeleton for the
        # subsumed table, holding the same answer `an` in A2 against several suspensions.
        if sp.instance !== nothing && an != 0
            if can != an                            # reuse the answer
                can != 0 && Undo!(ld, m)
                tbl_unify_answer(ld, atrie, an, A2) || @goto out_fail   # resource error
                can = an
            end

            if !state.keys_inited
                k, w, _ = _deref_loc(ld, -(A2 + 1)) # Word p = valTermRef(A2); deRef(p)
                @assert k == DU_WORD && _is_gcompound(w)
                fp = valPtr(w)
                arity = arityFunctor(ld.functors, ld.gstack[fp])
                arity > SINDEX_MAX && (arity = SINDEX_MAX)
                for i in 0:(arity - 1)
                    ak, aw, ap = _deref_loc(ld, fp + 1 + i)
                    state.keys[i + 2] = sindex_key(
                        UInt32(0), _sindex_word_key(ld, ak, aw, ap)
                    )
                end
                state.keys_inited = true
            end

            skeys = state.keys                      # key args are one based: entry i+1 is argument i

            while true
                if suspension_matches_index(ld, sp, skeys, A2)
                    rc = suspension_matches(ld, A2, sp)
                    rc == 1 && @goto match
                    rc != 0 && @goto out_fail
                end

                if wkl_next_suspension(state)
                    sp = get_suspension_from_cluster(state.scp::cluster{T}, state.here)
                    sp.instance === nothing && @goto match
                else
                    @goto next
                end
            end
        end

        # Found real work to do. If we get here we can only fail due to resource errors.
        @label match
        if can != 0 && can != an                    # A2 holds another answer
            Undo!(ld, m)
            can = 0
        end
        attvars = ld.attvar_attvars
        susp = PL_new_term_ref(ld)
        PL_recorded(ld, sp.term, susp) || @goto out_fail   # resource errors
        if ld.attvar_attvars != attvars && can != an       # the skeleton has constraints: unify
            tbl_unify_answer(ld, atrie, an, A2) || @goto out_fail
            can = an
        end
        # unifies A2..A6
        unify_dependency(ld, A2, susp, state.list::tbl_worklist{T}, an, can == an) ||
            @goto out_fail

        if advance_wkl_state(ld, state)
            return PL_retry_address(idx)            # ForeignRedoPtr(state)
        else
            free_wkl_state(ld, idx)
            return FTRUE
        end

        @label next
        advance_wkl_state(ld, state) || break
    end

    @label out_fail
    free_wkl_state(ld, idx)

    return FFALSE
end

# ---- TB2b: completing a component (pl-tabling.c:6226-6255, :6295-6324, :6440-6563 at the pin) ----

# PORT: pl-tabling.c wls_reeval_complete
# (pl-tabling.c:6226-6255 at the pin)
# DIVERGES: the IDG node (`atrie->data.IDG`) is TB6's: `atrie.IDG` is `nothing` for every table until then, so neither loop
# finds a re-evaluating node; a table with one is refused by name (`reeval_complete`, pl-tabling.c:11341, and the node's
# `reevaluating` and `falsecount` are TB6's).
"Finish the re-evaluation of the re-evaluated tables of the worklists `wls` (pl-tabling.c `wls_reeval_complete`)."
function wls_reeval_complete(
    ld::PL_local_data{T}, wls::Vector{tbl_worklist{T}}
)::Nothing where {T}
    for wl in wls
        atrie = wl_table(ld, wl)
        if atrie.IDG !== nothing                    # if ( (n=atrie->data.IDG) ) { if ( n->reevaluating ) ...
            throw(
                NotPortedError{T}(
                    mk_sym(T, :reeval_complete),
                    "reeval_complete (pl-tabling.c:11341)",
                    "TB6"
                )
            )
        end
    end

    return nothing
end

# PORT: pl-tabling.c unify_leader_clause
# (pl-tabling.c:6295-6324 at the pin)
# Owner: TB2. Its only caller at the pin is `table_complete_all` (:6463); TB3's `complete_answer_clause` is a
# separate function.
# DIVERGES: the result is `(rc, is_trie)` (upstream: the truth value and `*is_trie`); the leader is the trie numbered
# `scc.leader` in `gd.tries`; `atrie->data.worklist` holds a worklist, NULL (`nothing`) or a sentinel (an `Int`, TB1);
# `O_TRIE_STATS` is on (`gen_call` counts); `PL_unify_atom(cl, trie_symbol(atrie))` is pl-trie.c `unify_trie` (TR4's
# `unify_trie`, the same unification); the clause reference is TR4's `compile_trie(gd, ld, def, atrie)`, an atom word,
# 0 when the clause is refused (then false, upstream unifies its 0). `GD->procedures.trie_gen_compiled2` is
# `gd.procedures_trie_gen_compiled2` (as TB3's `complete_answer_clause`).
"Unify `cl` with the answer trie of the leader of `scc` or its compiled clause; the result and whether `cl` is the trie (pl-tabling.c `unify_leader_clause`)."
function unify_leader_clause(
    ld::PL_local_data{T}, scc::tbl_component{T}, cl::term_t
)::Tuple{Bool, Bool} where {T}
    gd = _query_gd(ld)
    atrie = gd.tries[scc.leader]
    wl = atrie.worklist

    is_trie = false
    atrie.gen_call += 1                             # TRIE_STAT_INC(atrie, gen_call)
    defined = !(wl isa tbl_worklist{T}) || wl.undefined == 0

    clref = atrie.clause
    as_trie = false
    if clref == 0 && (atrie.flags & (TRIE_ISSHARED | TRIE_ABOLISH_ON_COMPLETE)) == 0
        if atrie.IDG !== nothing                    # atrie->data.IDG ? ... : ...
            as_trie =
                defined && (atrie.flags & TRIE_ISMAP) == 0 &&
                atrie.value_count == 1 && trie_single_value_node(atrie) != 0
        else
            as_trie =
                (atrie.flags & TRIE_ISMAP) != 0 ||
                (
                    defined &&
                    div(atrie.node_count, atrie.value_count + 1) <
                    ld.table_flags_compile_threshold
                )
        end
    end
    if as_trie
        is_trie = true
        return unify_trie(gd, ld, cl, atrie), is_trie   # see (*)
    end

    def = gd.procedures_trie_gen_compiled2.definition::Definition{T}
    clref = compile_trie(gd, ld, def, atrie)
    clref == 0 && return false, is_trie

    return PL_unify_atomic(ld, cl, _atom_value(ld, clref)), is_trie
end

# PORT: pl-tabling.c table_complete_all
# (pl-tabling.c:6440-6533 at the pin; the DEBUG print is left out)
# DIVERGES: `skel` 0 is upstream's NULL (not for a leader); the leader is the trie numbered `c.leader` in `gd.tries`; a
# worklist's `table` 0 is upstream's NULL. Called with their upstream contracts, owned by the steps named:
# `destroy_answer_trie` (pl-tabling.c:4472) and `sweep_orphan_dynamic_tables` (:4598) TB1's, `trie_maybe_discard_nodes`
# (pl-trie.h:340) TR4's, `droppable_table` (:6350) and `drop_intermediate_tables` (:6374) the drop step's (TB8);
# `LD->table_flags.drop_intermediate` is `ld.table_flags_drop_intermediate` (TB1).
"Complete the tables the component `scc` created: its status, and for a leader (`skel` not 0) how to return its answers in `status` and `cl` (pl-tabling.c `table_complete_all`)."
function table_complete_all(
    ld::PL_local_data{T}, scc::term_t, status::term_t, cl::term_t, skel::term_t
)::Bool where {T}
    for_leader = skel != 0
    is_trie = false

    c = get_scc(ld, scc)
    c === nothing && return false

    if c.status == SCC_ACTIVE
        wls = worklist_set_to_array(c.created_worklists, T)
        ntables = length(wls)

        leader = _query_gd(ld).tries[c.leader]
        leader_stays = (leader.flags & TRIE_ABOLISH_ON_COMPLETE) == 0

        wls_reeval_complete(ld, wls)
        rc, is_trie = unify_leader_clause(ld, c, cl)

        for i in 1:ntables
            wl = wls[i]
            atrie = wl_table(ld, wl)

            if (atrie.flags & TRIE_ABOLISH_ON_COMPLETE) != 0
                atrie.worklist = nothing
                wl.table = 0
                destroy_answer_trie(ld, atrie)
                free_worklist(ld, wl)
            else
                destroy = wl.undefined == 0 && isempty(wl.delays)   # see (*)

                complete_worklist(ld, wl, destroy)
            end
        end
        reset_newly_created_worklists(ld, c, Int(WLFS_FREE_NONE))
        set_component_status(ld, c, SCC_COMPLETED)
        (rc && leader_stays) && trie_maybe_discard_nodes(_query_gd(ld), leader)   # compiled by unify_leader_clause()
        c.inferences = ld.statistics.inferences - c.inferences
        if ld.table_flags_drop_intermediate != 0
            if c.parent !== nothing
                if rc && ntables == 1 && leader_stays &&
                    (leader.flags & (TRIE_DISCARDABLE | TRIE_DISCARDED)) != 0 &&
                    leader.IDG === nothing
                    droppable_table(c, leader)
                end
            else
                drop_intermediate_tables(ld, c)
            end
        end

        (c.parent !== nothing && ld.tabling.component === c) &&
            (ld.tabling.component = c.parent)
        if c.parent === nothing
            ld.tabling.has_scheduling_component = false
            ld.tabling.active_components == 0 && sweep_orphan_dynamic_tables(ld)
        end

        rc || return false

        if for_leader
            if is_trie
                leader.value_count == 0 &&
                    return PL_unify_atom(ld, status, mk_sym(T, Symbol("false")))
                answer = trie_single_value_node(leader)
                if answer != 0
                    ok, _ = unify_trie_term(ld, leader, answer, skel)
                    return ok && PL_unify_atom(ld, status, mk_sym(T, Symbol("true")))
                end
            end
            return PL_unify_atom(ld, status, mk_sym(T, is_trie ? :trie : :clause))
        end
    end

    (for_leader && c.status == SCC_MERGED) &&
        return PL_unify_atom(ld, status, mk_sym(T, :merged))

    return unify_component_status(ld, status, c)
end

# PORT: pl-tabling.c tbl_table_complete_all as pl_tbl_table_complete_all3_va
# (pl-tabling.c:6535-6540 at the pin: PRED_IMPL("$tbl_table_complete_all", 3, tbl_table_complete_all, 0))
"`'\$tbl_table_complete_all'(+SCC, -Status, -Clause)`: complete and reset the tables `SCC` created; `Status` is merged, complete or final, `Clause` the leader's answer trie or its compiled clause (pl-tabling.c)."
function pl_tbl_table_complete_all3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2

    return table_complete_all(ld, A1, A2, A3, term_t(0)) ? FTRUE : FFALSE
end

# PORT: pl-tabling.c tbl_leader_complete as pl_tbl_leader_complete4_va
# (pl-tabling.c:6558-6563 at the pin: PRED_IMPL("$tbl_leader_complete", 4, tbl_leader_complete, 0))
"`'\$tbl_leader_complete'(+SCC, ?Skeleton, -Status, -Clause)`: as `'\$tbl_table_complete_all'/3` for the leader, `Status` true (the single answer unified with `Skeleton`), false, trie, clause or merged (pl-tabling.c)."
function pl_tbl_leader_complete4_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3, A4 = PL__t0, PL__t0 + 1, PL__t0 + 2, PL__t0 + 3

    return table_complete_all(ld, A1, A3, A4, A2) ? FTRUE : FFALSE
end

# ---- TB2b: freeing and discarding a component, the leader's cleanup, subcomponents (pl-tabling.c:6572-6728 at the pin) ----

# PORT: pl-tabling.c tbl_free_component as pl_tbl_free_component1_va
# (pl-tabling.c:6571-6584 at the pin: PRED_IMPL("$tbl_free_component", 1, tbl_free_component, 0))
"`'\$tbl_free_component'(+SCC)`: free the top component `SCC` if it is the current one (pl-tabling.c)."
function pl_tbl_free_component1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    c = get_scc(ld, A1)
    if c !== nothing
        @assert c.parent === nothing
        ld.tabling.component === c && free_component(ld, c, Int(FC_DESTROY))
        @assert ld.tabling.component === nothing
        return FTRUE
    end

    return FFALSE
end

# PORT: pl-tabling.c table_discard_all
# (pl-tabling.c:6595-6610 at the pin)
"Discard the tables `c` created and its worklists, after an exception in tabling; its parent becomes the current component (pl-tabling.c `table_discard_all`)."
function table_discard_all(ld::PL_local_data{T}, c::tbl_component{T})::Nothing where {T}
    if c.status != SCC_MERGED
        parent = c.parent

        c.created_worklists !== nothing &&
            reset_newly_created_worklists(ld, c, Int(WLFS_DISCARD_INCOMPLETE))
        reset_global_worklist(ld, c)

        ld.tabling.component = parent
        free_component(ld, c, Int(FC_DESTROY))

        parent === nothing && (ld.tabling.has_scheduling_component = false)
    end

    return nothing
end

# PORT: pl-tabling.c tbl_table_discard_all as pl_tbl_table_discard_all1_va
# (pl-tabling.c:6612-6621 at the pin: PRED_IMPL("$tbl_table_discard_all", 1, tbl_table_discard_all, 0))
"`'\$tbl_table_discard_all'(+SCC)`: discard the tables and worklists of `SCC` (pl-tabling.c)."
function pl_tbl_table_discard_all1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    c = get_scc(ld, A1)
    c !== nothing && table_discard_all(ld, c)

    return FTRUE
end

# PORT: pl-tabling.c tbl_leader_finished
# (pl-tabling.c:6638-6673 at the pin)
# DIVERGES: `set_idg_current` (pl-tabling.c:8328) is the IDG step's (TB6), assumed with its upstream contract; the message
# term `tabling(unexpected_result(Wrapper, Catcher))` is built by unification (upstream: `PL_FUNCTOR_CHARS` in printMessage).
"The cleanup of `'\$tbl_leader'/5`: on exit or failure free the completed top component `scc`, on an exception discard it (pl-tabling.c `tbl_leader_finished`)."
function tbl_leader_finished(
    ld::PL_local_data{T}, old::term_t, catcher::term_t, scc::term_t, wrapper::term_t
)::Bool where {T}
    gd = _query_gd(ld)
    set_idg_current(ld, get_trie_noex(gd, ld, old)) || return false

    a = PL_get_atom(ld, catcher)
    if a !== nothing &&
        (sym_key(a) == sym_key(mk_sym(T, :exit)) || sym_key(a) == sym_key(mk_sym(T, :fail)))
        c = ld.tabling.component
        if sym_key(a) == sym_key(mk_sym(T, :exit)) && c !== nothing &&
            tbl_get_pointer(ld, scc) === c &&   # PL_get_pointer(scc, &ptr) && ptr == (void*)c
            c.status == SCC_COMPLETED && c.parent === nothing
            free_component(ld, c, Int(FC_DESTROY))
            @assert ld.tabling.component === nothing
        end
        return true
    end

    if PL_is_functor(ld, catcher, mk_sym(T, :exception), 1)
        c = get_scc(ld, scc)
        c !== nothing && table_discard_all(ld, c)
        return true
    end

    msg = PL_new_term_ref(ld)
    a1 = PL_new_term_ref(ld)
    PL_unify_functor(ld, msg, mk_sym(T, :tabling), 1) || return false
    _PL_get_arg(ld, 1, msg, a1)
    PL_unify_functor(ld, a1, mk_sym(T, :unexpected_result), 2) || return false
    a2 = PL_new_term_ref(ld)
    _PL_get_arg(ld, 1, a1, a2)
    PL_unify(ld, a2, wrapper) || return false
    _PL_get_arg(ld, 2, a1, a2)
    PL_unify(ld, a2, catcher) || return false

    return printMessage(ld, :error, msg)
end

# PORT: pl-tabling.c tbl_create_subcomponent
# (pl-tabling.c:6676-6698 at the pin)
# DIVERGES: `leader` is the trie's number in `gd.tries` (`tbl_component.leader`, an index).
"A component led by `leader`: the scheduling component the first time, else a child of the current one (pl-tabling.c `tbl_create_subcomponent`)."
function tbl_create_subcomponent(
    ld::PL_local_data{T}, leader::trie{T}
)::tbl_component{T} where {T}
    tab = ld.tabling
    if !tab.has_scheduling_component
        tab.has_scheduling_component = true
        cur = tab.component
        if cur === nothing || tab.in_answer_completion
            cur = new_component(ld)
            tab.component = cur
        else
            set_component_status(ld, cur, SCC_ACTIVE)
        end
        cur.leader = leader.serial
        cur.inferences = ld.statistics.inferences
    else
        c = new_component(ld)
        c.leader = leader.serial
        c.inferences = ld.statistics.inferences
        p = tab.component::tbl_component{T}
        c.parent = p
        tab.component = c
        add_child_component(p, c)
    end

    return tab.component::tbl_component{T}
end

# PORT: pl-tabling.c unify_component_status
# (pl-tabling.c:6701-6721 at the pin)
"Unify `t` with the status of `scc`: active, merged, complete (with a parent) or final (pl-tabling.c `unify_component_status`)."
function unify_component_status(
    ld::PL_local_data{T}, t::term_t, scc::tbl_component{T}
)::Bool where {T}
    if scc.status == SCC_ACTIVE
        status = :active
    elseif scc.status == SCC_MERGED
        status = :merged
    elseif scc.status == SCC_COMPLETED
        status = scc.parent !== nothing ? :complete : :final
    else
        @assert false
        return false
    end

    return PL_unify_atom(ld, t, mk_sym(T, status))
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

# ---- TB2b: inspecting tabling data (pl-tabling.c:6767-6932 at the pin) ----

# PORT: pl-tabling.c tbl_scc as pl_tbl_scc1_va
# (pl-tabling.c:6771-6779 at the pin: PRED_IMPL("$tbl_scc", 1, tbl_scc, 0))
"`'\$tbl_scc'(-SCC)`: `SCC` is the handle of the current component; false without one (pl-tabling.c)."
function pl_tbl_scc1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    c = ld.tabling.component
    c !== nothing && return tbl_unify_pointer(ld, A1, c) ? FTRUE : FFALSE

    return FFALSE
end

# PORT: pl-tabling.c unify_wl_set
# (pl-tabling.c:6781-6796 at the pin)
"Unify `l` with the list of the handles of the worklists of `wls` (pl-tabling.c `unify_wl_set`)."
function unify_wl_set(
    ld::PL_local_data{T}, l::term_t, wls::Union{Nothing, worklist_set{tbl_worklist{T}}}
)::Bool where {T}
    p = worklist_set_to_array(wls, T)
    n = length(p)

    tail = PL_copy_term_ref(ld, l)
    head = PL_new_term_ref(ld)
    for i in 1:n
        if !PL_unify_list(ld, tail, head, tail) || !tbl_unify_pointer(ld, head, p[i])
            return false
        end
    end

    return PL_unify_nil(ld, tail)
end

# PORT: pl-tabling.c unify_scc_set
# (pl-tabling.c:6798-6816 at the pin)
"Unify `l` with the list of the handles of the components of `cs`, [] for none (pl-tabling.c `unify_scc_set`)."
function unify_scc_set(
    ld::PL_local_data{T}, l::term_t, cs::Union{Nothing, component_set{tbl_component{T}}}
)::Bool where {T}
    tail = PL_copy_term_ref(ld, l)

    if cs !== nothing
        head = PL_new_term_ref(ld)

        for c in cs.members
            if !PL_unify_list(ld, tail, head, tail) || !tbl_unify_pointer(ld, head, c)
                return false
            end
        end
    end

    return PL_unify_nil(ld, tail)
end

# PORT: pl-tabling.c unify_pointer_or_nil
# (pl-tabling.c:6818-6826 at the pin)
"Unify `t` with the handle of the component `ptr`, or the atom `null` for none (pl-tabling.c `unify_pointer_or_nil`)."
function unify_pointer_or_nil(
    ld::PL_local_data{T}, t::term_t, ptr::Union{Nothing, tbl_component{T}}
)::Bool where {T}
    if ptr !== nothing
        return tbl_unify_pointer(ld, t, ptr)
    else
        return PL_unify_atom(ld, t, mk_sym(T, :null))   # PL_unify_atom_chars(t, "null")
    end
end

# PORT: pl-tabling.c tbl_scc_data as pl_tbl_scc_data2_va
# (pl-tabling.c:6828-6847 at the pin: PRED_IMPL("$tbl_scc_data", 2, tbl_scc_data, 0))
"`'\$tbl_scc_data'(+SCC, -Data)`: `Data` is scc(Parent, Children, Status, Worklist, CreatedWorklists) of the component `SCC` (pl-tabling.c)."
function pl_tbl_scc_data2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    scc = get_scc(ld, A1)

    if scc !== nothing
        av = PL_new_term_refs(ld, 5)
        t = PL_new_term_ref(ld)
        scc5 = lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :scc)), 5)   # FUNCTOR_scc5

        return if (
            unify_pointer_or_nil(ld, av + 0, scc.parent) &&
            unify_scc_set(ld, av + 1, scc.children) &&
            unify_component_status(ld, av + 2, scc) &&
            unify_wl_set(ld, av + 3, scc.worklist) &&
            unify_wl_set(ld, av + 4, scc.created_worklists) &&
            PL_cons_functor_v(ld, t, scc5, av) &&
            PL_unify(ld, t, A2)
        )
            FTRUE
        else
            FFALSE
        end
    end

    return FFALSE
end

# PORT: pl-tabling.c unify_cluster
# (pl-tabling.c:6850-6892 at the pin)
# DIVERGES: an answer is a node id of the worklist's answer trie, passed as `atrie` (upstream: the node, which knows its trie);
# `tbl_unify_answer(ld, atrie, nid, term)` is TB3's (pl-tabling.c `tbl_unify_answer`); `PL_unify_term(t, PL_FUNCTOR_CHARS,
# "riac", 1, PL_TERM, a)` is `PL_unify_functor` then `PL_unify_arg`; `UNTNOT(sp->term)` is `sp.term`.
"Unify `t` with the list of the answers or suspension goals of the cluster `c`, wrapped in riac/1 when `is_riac` (pl-tabling.c `unify_cluster`)."
function unify_cluster(
    ld::PL_local_data{T}, t::term_t, atrie::trie{T}, c::cluster{T}, is_riac::Bool
)::Bool where {T}
    if is_riac
        a = PL_new_term_ref(ld)
        if !(PL_unify_functor(ld, t, mk_sym(T, :riac), 1) && PL_unify_arg(ld, 1, t, a))
            return false
        end
        t = a
    end

    tail = PL_copy_term_ref(ld, t)
    head = PL_new_term_ref(ld)

    if c.type == CLUSTER_ANSWERS
        for an in c.answers
            if !PL_unify_list(ld, tail, head, tail) ||
                !tbl_unify_answer(ld, atrie, an, head)
                return false
            end
        end
        return PL_unify_nil(ld, tail)
    else
        tmp = PL_new_term_ref(ld)

        @assert c.type == CLUSTER_SUSPENSIONS

        for sp in c.suspensions
            if !PL_unify_list(ld, tail, head, tail) || !PL_recorded(ld, sp.term, tmp) ||
                !PL_unify(ld, tmp, head)
                return false
            end
        end
        return PL_unify_nil(ld, tail)
    end
end

# PORT: pl-tabling.c unify_clusters
# (pl-tabling.c:6895-6909 at the pin)
"Unify `t` with the list of the clusters of the worklist `wl` (pl-tabling.c `unify_clusters`)."
function unify_clusters(
    ld::PL_local_data{T}, t::term_t, wl::tbl_worklist{T}
)::Bool where {T}
    tail = PL_copy_term_ref(ld, t)
    head = PL_new_term_ref(ld)
    atrie = wl_table(ld, wl)

    c = wl.head
    while c !== nothing
        if !PL_unify_list(ld, tail, head, tail) ||
            !unify_cluster(ld, head, atrie, c, c === wl.riac)
            return false
        end
        c = c.next
    end

    return PL_unify_nil(ld, tail)
end

# PORT: pl-tabling.c tbl_worklist_data as pl_tbl_worklist_data2_va
# (pl-tabling.c:6912-6932 at the pin: PRED_IMPL("$tbl_worklist_data", 2, tbl_worklist_data, 0))
# DIVERGES: `PL_unify_atomic(av+1, trie_symbol(wl->table))` is TR4's `unify_trie` (the same unification); a worklist without a
# component (`wl->component` NULL; upstream unifies the integer `PL_unify_pointer` makes of NULL) unifies 0.
"`'\$tbl_worklist_data'(+Worklist, -Data)`: `Data` is worklist(SCC, Trie, InGlobal, Executing, Clusters) of `Worklist` (pl-tabling.c)."
function pl_tbl_worklist_data2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    wl = get_worklist(ld, A1)

    if wl !== nothing
        av = PL_new_term_refs(ld, 5)
        t = PL_new_term_ref(ld)
        worklist5 = lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :worklist)), 5)   # FUNCTOR_worklist5
        c = wl.component
        comp_ok =
            c === nothing ? PL_unify_int64(ld, av + 0, 0) : tbl_unify_pointer(ld, av + 0, c)

        return if (
            comp_ok &&
            unify_trie(_query_gd(ld), ld, av + 1, wl_table(ld, wl)) &&
            PL_unify_bool(ld, av + 2, wl.in_global_wl) &&
            PL_unify_bool(ld, av + 3, wl.executing) &&
            unify_clusters(ld, av + 4, wl) &&
            PL_cons_functor_v(ld, t, worklist5, av) &&
            PL_unify(ld, t, A2)
        )
            FTRUE
        else
            FFALSE
        end
    end

    return FFALSE
end

# PORT: pl-tabling.c tbl_wkl_table as pl_tbl_wkl_table2_va
# (pl-tabling.c:6935-6942 at the pin: PRED_IMPL("$tbl_wkl_table", 2, tbl_wkl_table, 0))
# DIVERGES: `PL_unify_atomic(A2, trie_symbol(wl->table))` is TR4's `unify_trie` (the same unification), as in
# `'\$tbl_worklist_data'/2`.
"`'\$tbl_wkl_table'(+Worklist, -Trie)`: `Trie` is the answer trie of `Worklist` (pl-tabling.c)."
function pl_tbl_wkl_table2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    wl = get_worklist(ld, A1)

    return if (wl !== nothing && unify_trie(_query_gd(ld), ld, A2, wl_table(ld, wl)))
        FTRUE
    else
        FFALSE
    end
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

# PORT: pl-tabling.c reset_answer_table
# DIVERGES: the worklist branch (an answer table with a worklist) is refused by name, owner TB5 (the abolish callers hold the
# engine `ld` that `destroy_depending_worklists`, `destroy_delay_info_worklist` and `free_worklist` need; this function and the
# release chain above it carry only `gd`; docs/architecture.md TAB1 TB2, "named refusal"); a sentinel (WL_GROUND, WL_DYNAMIC) is
# `data.worklist = Int` and is made fresh again; the IDG node is refused by name, owner TB6 (`idg_reset`, `idg_destroy`,
# `idg_destroy_private`), the tracked table (`tt_abolish_table`) owner TB9.
"Make the answer table `atrie` fresh again: no worklist, not complete, no answers (pl-tabling.c)."
function reset_answer_table(
    gd::PL_global_data{T}, atrie::trie{T}, flags::Int
)::Nothing where {T}
    wl = atrie.worklist
    if wl isa Int
        atrie.worklist = nothing                # make fresh again
    elseif wl !== nothing
        tbl_refuse(
            T,
            :reset_answer_table,
            "reset_answer_table: a table with a worklist (destroy_depending_worklists, free_worklist: the engine)",
            "TB5"
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

    trie_empty(gd, atrie)

    return nothing
end

# PORT: pl-tabling.c release_variant_table_node
# DIVERGES: the answer trie is found by number in the table's `registry`; the node is a node id, the node's `variant` link
# of the answer trie is the node id (0: NULL).
"Release the answer table of node `nid` of the variant table `variant_table` (pl-tabling.c)."
function release_variant_table_node(
    gd::PL_global_data{T}, variant_table::trie{T}, nid::Int
)::Nothing where {T}
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
        reset_answer_table(gd, atrie, variant_table.magic == TRIE_CMAGIC ? RAT_CLEANUP : 0)
        @assert atrie.variant == nid
        atrie.variant = 0
    end

    return nothing
end

# PORT: pl-tabling.c is_variant_trie
"Whether `tr` is a variant table (pl-tabling.c `is_variant_trie`)."
is_variant_trie(tr::trie)::Bool = (tr.flags & TRIE_ISVARIANT) != 0

# PORT: pl-tabling.c release_answer_node
# (pl-tabling.c:2511-2515 at the pin) DIVERGES: the node is a node id and the database an argument (`node_delayinfo`, `destroy_delay_info`).
"Release the tabling data of node `nid` of the answer trie `atrie`: the delay information of a conditional answer goes (pl-tabling.c)."
function release_answer_node(
    gd::PL_global_data{T}, atrie::trie{T}, nid::Int
)::Nothing where {T}
    if DL_IS_DELAY_LIST(node_delayinfo(gd, atrie, nid))
        destroy_delay_info(gd, atrie, nid, true)
    end

    return nothing
end

# PORT: pl-tabling.c tbl_release_node
"Called by the trie code when node `nid` of the answer trie or variant table `tr` is released (pl-tabling.c)."
function tbl_release_node(gd::PL_global_data{T}, tr::trie{T}, nid::Int)::Nothing where {T}
    if is_variant_trie(tr)
        release_variant_table_node(gd, tr, nid)
    else
        release_answer_node(gd, tr, nid)
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

# ---- TB3: answers, answer subsumption (moded tables), S_TABLED support (pl-tabling.c at 18168e62) ----
# ORIGINAL (TAB1 TB3): the code of later steps this part reaches is refused by name with TB1's `tbl_refuse` (owner in the
# message): the delay lists of WFS (TB4), the restraint tripwires (TB8), the IDG (TB6). Interfaces of the parallel steps it
# calls (TB2: `wl_table`, `get_worklist`, `wkl_add_answer`, `prune_answers_worklist`; TR1: `trie_insert_flat`,
# `trie_lookup_abstract`, `trie_lookup`, `trie_delete`, `set_trie_value_word`, `unify_trie_term`, `put_trie_value`,
# `prune_trie`, `map_trie_node`) are listed in evidence/TB3/handoff.md.

# PORT: pl-tabling.c UDL_FALSE
"`update_delay_list` result: an error (pl-tabling.c `udl_status`)."
const UDL_FALSE = 0
# PORT: pl-tabling.c UDL_TRUE
"`update_delay_list` result: done (pl-tabling.c `udl_status`)."
const UDL_TRUE = 1
# PORT: pl-tabling.c UDL_COMPLETE
"`update_delay_list` result: the answer completes the table (early completion, pl-tabling.c `udl_status`)."
const UDL_COMPLETE = 2

# ORIGINAL (TAB1 TB3): pl-tabling.c `deRef2(valTermRef(LD->tabling.delay_list), gdlp); gdlp = argTermP(*gdlp, 0)` and `isNil`:
# whether the global delay list (argument 1 of the term in `ld.tabling.delay_list`) is `[]`.
# DIVERGES: `ld.tabling.delay_list` is 0 until the term reference is created (TB4's `$tbl_set_delay_list/1` and initTabling's
# owner): 0 reads as the empty list.
"Whether the global delay list of this thread is empty (pl-tabling.c `isNil(*gdlp)`)."
function global_delay_list_is_nil(ld::PL_local_data{T})::Bool where {T}
    dl = ld.tabling.delay_list
    dl == 0 && return true
    a = PL_new_term_ref(ld)
    _PL_get_arg(ld, 1, dl, a) || return true

    return PL_get_nil(ld, a)
end

# PORT: pl-tabling.c pred_max_table_answer_size
# DIVERGES: `(size_t)-1` is -1 (as `table_props`).
"The answer size limit of `def`: its `answer_abstract`, else the restraint; -1: none (pl-tabling.c)."
function pred_max_table_answer_size(ld::PL_local_data, def::Definition)::Int
    limit = def.tabling !== nothing ? def.tabling.answer_abstract : -1
    if limit == -1
        limit = ld.tabling.restraint.max_table_answer_size
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
# DIVERGES: `create` true is `_unify_fresh_create` (TB2: `tripwire_incomplete_subgoals`, `tbl_create_subcomponent`,
# `tbl_add_worklist`, the pointers as handles).
"Unify `t` with `fresh`, or with `fresh(SCC, WL)` when `create` (pl-tabling.c)."
function unify_fresh(
    ld::PL_local_data{T}, t::term_t, atrie::trie{T}, def::Union{Nothing, Definition{T}},
    create::Bool
)::Bool where {T}
    create && return _unify_fresh_create(ld, t, atrie, def)

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
# DIVERGES: the worklist is unified as its handle (`tbl_unify_pointer`, upstream `PL_unify_pointer(t, wl)`).
"Unify `t` with the status of `atrie`: `complete`, `invalid`, `dynamic` or `fresh`, a worklist for an incomplete table (pl-tabling.c)."
function unify_table_status(
    ld::PL_local_data{T}, t::term_t, atrie::trie{T}, def::Union{Nothing, Definition{T}},
    create::Bool
)::Bool where {T}
    if (atrie.flags & TRIE_COMPLETE) != 0
        return unify_complete_or_invalid(ld, t, atrie, def, create)
    else
        wl = atrie.worklist
        if wl isa tbl_worklist
            if create && wl.component !== ld.tabling.component
                size0 = wls_size((wl.component::tbl_component{T}).created_worklists)
                merge_component(ld, wl.component::tbl_component{T})
                ld.tabling.component = wl.component
                tripwire_scc_subgoals(ld, wl, size0) || return false
            end

            return tbl_unify_pointer(ld, t, wl)
        end
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

# ---- the destruction of a table and the orphan sweep: called by TB2 and TB4, owned by TB5 (pl-tabling.c:4472-4690) ----
# NOTE: a minimal port of the functions batch 3 calls (`table_complete_all`, `destroy_depending_worklists`), taken from pl-tabling.c at
# the pin; TB5 supersedes them with the rest of the abolish steps (`abolish_table`, `collect_dynamic_children`, the shared
# tables), as `'\$idg_set_current'/2` is TB6's. `droppable_table` and `drop_intermediate_tables` (the flag
# `table_drop_intermediate`) are refused by name, owner TB8, below.

# PORT: pl-tabling.c DYN_ORPHAN_SWEEP_MIN
"The number of dynamic nodes that lost a dependent from which a completed root component sweeps the orphans (pl-tabling.c)."
const DYN_ORPHAN_SWEEP_MIN = 1024

# ORIGINAL (TAB1 TB5): whether the worklist slot of `atrie` holds the sentinel `s` (`WL_GROUND`, `WL_DYNAMIC`: an `Int` in the slot).
@inline function _wl_is(atrie::trie, s::Int)::Bool
    w = atrie.worklist
    return w isa Int && w == s
end

# PORT: pl-trie.c get_trie_from_node
# DIVERGES: the node id `atrie.variant` is a node of the thread's variant table (the private one: a shared table is refused by
# name, owner TH1), so the trie is `gd.tries[ld.tabling.variant_table]`; upstream finds the trie of a node by walking up to the
# root chunk. `nothing` when the thread has no variant table (it was cleared).
"The variant table the node `atrie.variant` belongs to, or `nothing` (pl-trie.c `get_trie_from_node`)."
function get_trie_from_node(
    ld::PL_local_data{T}, atrie::trie{T}
)::Union{Nothing, trie{T}} where {T}
    (atrie.flags & TRIE_ISSHARED) != 0 && tbl_refuse(
        T, :get_trie_from_node,
        "get_trie_from_node: the node of a shared variant table", "TH1"
    )
    vi = ld.tabling.variant_table
    vi == 0 && return nothing

    return _query_gd(ld).tries[vi]
end

# PORT: pl-tabling.c reset_answer_table as reset_answer_table_worklist
# (pl-tabling.c:2642-2652 at the pin: the `WL_IS_WORKLIST` branch; the call site is `release_variant_table_node`, :2689, reached
# from `trie_delete` in `destroy_answer_trie`, :4486.)
# DIVERGES: the branch needs the engine (`destroy_depending_worklists`, `free_worklist`), which the release chain of `trie_delete`
# does not carry (`reset_answer_table`'s refusal, owner TB5); `destroy_answer_trie` holds it and runs the branch before the delete,
# so the chain finds no worklist. TB5's abolish callers do the same or carry the engine through the chain (owner TB5).
"The worklist branch of `reset_answer_table`: the worklist of `atrie` and the tables that depend on it go (pl-tabling.c)."
function reset_answer_table_worklist(
    ld::PL_local_data{T}, atrie::trie{T}, flags::Int
)::Nothing where {T}
    wl = atrie.worklist
    if wl isa tbl_worklist{T}
        if !isempty(wl.delays) && (flags & RAT_CLEANUP) == 0
            destroy_depending_worklists(ld, wl)
        end
        wl.undefined != 0 && destroy_delay_info_worklist(_query_gd(ld), wl)
        atrie.worklist = nothing
        atrie.flags &= ~TRIE_ABOLISH_ON_COMPLETE
        free_worklist(ld, wl)
    end

    return nothing
end

# PORT: pl-tabling.c destroy_answer_trie
# (pl-tabling.c:4472-4492 at the pin.)
# DIVERGES: the shared branch (`COMPLETE_WORKLIST(reset_answer_table)`) is refused by name, owner TH1.
"Delete the node of the answer trie `atrie` from its variant table; whether there was one (pl-tabling.c)."
function destroy_answer_trie(ld::PL_local_data{T}, atrie::trie{T})::Bool where {T}
    if atrie.variant != 0
        vtrie = get_trie_from_node(ld, atrie)
        if vtrie !== nothing && is_variant_trie(vtrie)
            (atrie.flags & TRIE_ISSHARED) != 0 &&
                tbl_refuse(
                    T, :destroy_answer_trie, "destroy_answer_trie: a shared table", "TH1"
                )
            reset_answer_table_worklist(
                ld, atrie, vtrie.magic == TRIE_CMAGIC ? RAT_CLEANUP : 0
            )
            trie_delete(_query_gd(ld), vtrie, atrie.variant, true)

            return true
        end
    end

    return false
end

# PORT: pl-tabling.c delayed_destroy_table
# (pl-tabling.c:4495-4505 at the pin.)
"If `atrie` is incomplete, schedule its destruction for when it completes; whether it was scheduled (pl-tabling.c)."
function delayed_destroy_table(atrie::trie{T})::Bool where {T}
    if table_is_incomplete(atrie)
        atrie.flags |= TRIE_ABOLISH_ON_COMPLETE

        return true
    end

    return false
end

# PORT: pl-tabling.c orphan_dynamic_table
# DIVERGES: the IDG node (`atrie->data.IDG`, `idg_set_is_empty(&n->affected)`) is TB6's: `IDG` is `nothing` until then, so no table
# is an orphan dynamic table and this answers false.
"Whether the private dynamic pseudo table `atrie` has no dependent tables and may be deleted (pl-tabling.c)."
function orphan_dynamic_table(atrie::trie)::Bool
    return _wl_is(atrie, WL_DYNAMIC) &&
           atrie.variant != 0 &&
           (atrie.flags & TRIE_ISSHARED) == 0 &&
           atrie.IDG !== nothing                    # && idg_set_is_empty(&n->affected): TB6
end

# PORT: pl-tabling.c delete_dynamic_table
"Delete the dynamic pseudo table `atrie` from its variant table (pl-tabling.c)."
function delete_dynamic_table(ld::PL_local_data{T}, atrie::trie{T})::Nothing where {T}
    vtrie = get_trie_from_node(ld, atrie)
    if vtrie !== nothing && is_variant_trie(vtrie)
        trie_delete(_query_gd(ld), vtrie, atrie.variant, true)
    end

    return nothing
end

# PORT: pl-tabling.c delete_orphan_dynamic_tables
"Delete those of the tables `b` that are orphans (pl-tabling.c)."
function delete_orphan_dynamic_tables(
    ld::PL_local_data{T}, b::Vector{trie{T}}
)::Nothing where {T}
    for atrie in b
        orphan_dynamic_table(atrie) && delete_dynamic_table(ld, atrie)
    end

    return nothing
end

# PORT: pl-tabling.c sweep_orphan_dynamic_tables
# DIVERGES: upstream's callback `collect_orphan_dynamic_table(node, ctx)` is the closure over `b` here; `vtrie->value_count` is the
# trie's `value_count`.
"Delete all orphan dynamic pseudo tables once enough dynamic nodes lost a dependent (pl-tabling.c)."
function sweep_orphan_dynamic_tables(ld::PL_local_data{T})::Nothing where {T}
    gd = _query_gd(ld)
    vi = ld.tabling.variant_table
    vi == 0 && return nothing
    vtrie = gd.tries[vi]
    if ld.tabling.dyn_orphan_events >= DYN_ORPHAN_SWEEP_MIN &&
        ld.tabling.dyn_orphan_events >= vtrie.value_count
        b = trie{T}[]
        map_trie_node(vtrie, 1, function (tr, nid)
            v = tr.nodes[nid].value
            if v != 0
                atrie = value_trie(gd, v)
                orphan_dynamic_table(atrie) && push!(b, atrie)
            end

            return nothing
        end)
        delete_orphan_dynamic_tables(ld, b)
        ld.tabling.dyn_orphan_events = 0
    end

    return nothing
end

# PORT: pl-tabling.c droppable_table
# DIVERGES: refused by name, owner TB8 (the flag `table_drop_intermediate`, off by default).
function droppable_table(c::tbl_component{T}, leader::trie{T})::Union{} where {T}
    tbl_refuse(
        T, :droppable_table, "droppable_table: the flag table_drop_intermediate", "TB8"
    )
end

# PORT: pl-tabling.c drop_intermediate_tables
# DIVERGES: refused by name, owner TB8 (the flag `table_drop_intermediate`, off by default).
function drop_intermediate_tables(
    ld::PL_local_data{T}, c::tbl_component{T}
)::Union{} where {T}
    tbl_refuse(
        T,
        :drop_intermediate_tables,
        "drop_intermediate_tables: the flag table_drop_intermediate",
        "TB8"
    )
end

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
# set here: the table is always unified as symbol and `unify_table_status`. The closure-less call (e.g. `start_tabling(0, ...)`)
# gets its definition from `get_procedure_resolve` (src/pl-proc.jl, `get_procedure(variant, &proc, 0, GP_RESOLVE|GP_EXISTENCE_ERROR)`). `idg_init_variant` and
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
        proc = get_procedure_resolve(gd, ld, variant)   # get_procedure(variant, &proc, 0, GP_RESOLVE|GP_EXISTENCE_ERROR)
        proc === nothing && return false
        def = proc.definition
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

# PORT: pl-tabling.c tripwire_answers_for_subgoal
# DIVERGES: `NULL_ATOM` is `nothing`; `(size_t)-1` is -1.
"The action when the worklist's table reached its answer count limit, `nothing` if it did not (pl-tabling.c)."
function tripwire_answers_for_subgoal(
    ld::PL_local_data{T}, wl::tbl_worklist{T}
)::Union{Nothing, T} where {T}
    ps = (wl.predicate::Definition{T}).tabling
    if ps !== nothing && ps.max_answers != -1
        limit = ps.max_answers
        wl_table(ld, wl).value_count >= limit && return mk_sym(T, :bounded_rationality)
        return nothing
    end
    limit = ld.tabling.restraint.max_answers_for_subgoal
    if limit != -1
        wl_table(ld, wl).value_count == limit &&
            return ld.tabling.restraint.max_answers_for_subgoal_action
    end

    return nothing
end

# PORT: pl-tabling.c TBL_ANSWER_NEW
"`tbl_add_answer` result: a new answer (pl-tabling.c)."
const TBL_ANSWER_NEW = 1
# PORT: pl-tabling.c TBL_ANSWER_COMPLETE
"`tbl_add_answer` result: the answer completes the table (pl-tabling.c)."
const TBL_ANSWER_COMPLETE = 2

# PORT: pl-tabling.c tbl_add_answer
# (pl-tabling.c:4756-4771 at the pin.) The `O_PLMT` debug assertion is dropped (TH1).
"""
    tbl_add_answer(ld, wl, answer, delays) -> Int

Add `answer` with `delays` to the worklist `wl` and its answer trie: 0 (false) if it is a variant of an existing answer or on an
exception, `TBL_ANSWER_NEW` or `TBL_ANSWER_COMPLETE` (pl-tabling.c).
"""
function tbl_add_answer(
    ld::PL_local_data{T}, wl::tbl_worklist{T}, answer::term_t, delays::term_t
)::Int where {T}
    atrie = wl_table(ld, wl)
    if (atrie.flags & TRIE_ISMAP) != 0
        return wkl_mode_add_answer(ld, wl, atrie, answer, delays) != 0 ? TBL_ANSWER_NEW : 0
    end

    rc, nid = trie_insert_flat(ld, atrie, -(answer + 1))
    return tbl_add_answer_found(ld, wl, answer, delays, rc, nid)
end

# PORT: pl-tabling.c tbl_add_answer_found
# (pl-tabling.c:4777-4883 at the pin.)
# DIVERGES: nodes are ids; the restraint branches are TB8's and refused by name: the answer size tripwire `tbl_wl_tripwire` and
# `add_radial_restraint` (an abstracted answer whose action is not `fail`), and the answer count restraint
# (`generalise_answer_substitution`, `add_answer_count_restraint`, `tbl_wl_tripwire`). The IDG reevaluation branch is TB6's
# (`IDG` is `nothing` until then). The `goto update_dl` / `add_anyway` labels are `@goto`s.
"Continue `tbl_add_answer` after `trie_insert_flat` gave `rc` and `nid` (pl-tabling.c)."
function tbl_add_answer_found(
    ld::PL_local_data{T}, wl::tbl_worklist{T}, answer::term_t, delays::term_t, rc::Int,
    nid::Int
)::Int where {T}
    atrie = wl_table(ld, wl)
    complete = false

    if rc == TRIE_LOOKUP_NOT_FLAT
        sz = pred_max_table_answer_size(ld, wl.predicate::Definition{T})
        sa = size_abstract(2, sz == -1 ? typemax(Int) : sz)
        rc, nid = trie_lookup_abstract(ld, atrie, 0, -(answer + 1), true, sa, nothing)
    end
    if rc > 0                                       # ok or abstracted
        if rc == TRIE_ABSTRACTED
            action = ld.tabling.restraint.max_table_answer_size_action
            if sym_key(action) == sym_key(mk_sym(T, :fail))
                trie_delete(_query_gd(ld), atrie, nid, true)
                return 0
            end
            # ATOM_bounded_rationality: add_radial_restraint(); else tbl_wl_tripwire(wl, action, max_table_answer_size)
            tbl_refuse(
                T,
                :tbl_wl_tripwire,
                "tbl_add_answer: the answer size restraint (tbl_wl_tripwire, add_radial_restraint)",
                "TB8"
            )
        end

        nd = atrie.nodes[nid]
        if nd.value != 0
            if nd.value == ATOM_trienode
                if (nd.flags & TN_IDG_DELETED) != 0
                    nd.flags &= ~TN_IDG_DELETED
                    @goto update_dl
                else
                    if answer_is_conditional(_query_gd(ld), atrie, nid)
                        update_delay_list(ld, wl, nid, answer, delays) == UDL_COMPLETE &&
                            return TBL_ANSWER_COMPLETE
                    end
                end

                return 0                            # already in trie
            end
            PL_error(
                ld,
                "",
                0,
                "",
                ERR_PERMISSION,
                mk_sym(T, :modify),
                mk_sym(T, :trie_key),
                answer
            )
            return 0                                # return PL_permission_error("modify", "trie_key", answer)
        elseif (action = tripwire_answers_for_subgoal(ld, wl)) !== nothing
            # ATOM_bounded_rationality: generalise_answer_substitution, add_answer_count_restraint; else tbl_wl_tripwire
            tbl_refuse(
                T,
                :tbl_wl_tripwire,
                "tbl_add_answer: the answer count restraint (max_answers, max_answers_for_subgoal)",
                "TB8"
            )
        else
            set_trie_value_word(_query_gd(ld), atrie, nid, ATOM_trienode)
            # (idg = wl->table->data.IDG) && idg->reevaluating: TB6 (`IDG` is `nothing` until then)

            @label update_dl
            udl = update_delay_list(ld, wl, nid, answer, delays)
            if udl == UDL_FALSE
                return 0
            elseif udl == UDL_COMPLETE
                complete = true
            end

            wkl_add_answer(ld, wl, nid) || return 0
            return complete ? TBL_ANSWER_COMPLETE : TBL_ANSWER_NEW
        end
    end

    return trie_error(ld, rc, answer) ? 1 : 0
end

# PORT: pl-tabling.c tbl_wkl_add_answer as pl_tbl_wkl_add_answer4_va
# (PRED_IMPL("$tbl_wkl_add_answer", 4, tbl_wkl_add_answer, 0), pl-tabling.c:4885-4899 at the pin.)
"`'\$tbl_wkl_add_answer'(+Worklist, +Term, +Delays, -Complete)`: add an answer; `Complete` is `!` if it completes the table (pl-tabling.c)."
function pl_tbl_wkl_add_answer4_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    A2 = PL__t0 + 1
    A3 = PL__t0 + 2
    A4 = PL__t0 + 3

    wl = get_worklist(ld, A1)
    if wl !== nothing
        rc = tbl_add_answer(ld, wl, A2, A3)

        rc == TBL_ANSWER_COMPLETE &&
            return PL_unify_atom(ld, A4, mk_sym(T, Symbol("!"))) ? FTRUE : FFALSE
        return rc != 0 ? FTRUE : FFALSE
    end

    return FFALSE
end

# PORT: pl-tabling.c AS_NEW_DEFINED
"`'\$tabling':update/7` flag: the new answer is unconditional (pl-tabling.c)."
const AS_NEW_DEFINED = Int(0x1)
# PORT: pl-tabling.c AS_OLD_DEFINED
"`'\$tabling':update/7` flag: the old answer is unconditional (pl-tabling.c)."
const AS_OLD_DEFINED = Int(0x2)

# PORT: pl-tabling.c TRIE_MAP_FALSE
"`update_subsuming_answer` result: an error while mapping (pl-tabling.c; `TRIE_MAP_TRUE`, go on, is `nothing`)."
const TRIE_MAP_FALSE = 1
# PORT: pl-tabling.c TRIE_MAP_DONE
"`update_subsuming_answer` result: an existing answer subsumes the new one (pl-tabling.c)."
const TRIE_MAP_DONE = 2

# PORT: pl-tabling.c sa_context
# DIVERGES: nodes are ids (0: NULL); `wl` is `nothing` for monotonic tabling (upstream NULL); `delays` is 0 for monotonic tabling.
"The state of `update_subsuming_answers` while it maps the secondary nodes of an answer (pl-tabling.c `sa_context`)."
mutable struct sa_context{T}
    wl::Union{Nothing, tbl_worklist{T}}
    atrie::trie{T}
    root::Int
    added::Int
    skel::term_t
    delays::term_t
    argv::term_t
    flags::Int
    garbage::Int
end

# PORT: pl-tabling.c add_subsuming_answer
# (pl-tabling.c:5035-5079 at the pin.)
# DIVERGES: nodes are ids, the result is the added secondary node or 0 (upstream NULL); `old` is 0 for NULL; the error of the
# lookup names the trie through `unify_trie` (upstream `PL_unify_atomic(trie, trie_symbol(atrie))`).
"Add the aggregated moded arguments `margs` as a secondary node below `root`; the new node or 0 if nothing changed (pl-tabling.c)."
function add_subsuming_answer(
    ld::PL_local_data{T}, wl::Union{Nothing, tbl_worklist{T}}, atrie::trie{T}, root::Int,
    skel::term_t, old::Int,
    margs::term_t, delays::term_t
)::Int where {T}
    rc, nid = trie_lookup(ld, atrie, root, -(margs + 1), true, nothing)
    if rc == 1
        nd = atrie.nodes[nid]
        if (nd.flags & TN_SECONDARY) == 0
            nd.value = ATOM_trienode
            nd.flags |= TN_SECONDARY
            if old != 0
                trie_delete(_query_gd(ld), atrie, old, false)
            end
            if wl !== nothing
                update_delay_list(ld, wl, nid, skel, delays) == UDL_FALSE && return 0
                wkl_add_answer(ld, wl, nid)
            end
            return nid
        else
            if (nd.flags & TN_IDG_DELETED) != 0
                nd.flags &= ~TN_IDG_DELETED
            end
            if wl !== nothing && answer_is_conditional(_query_gd(ld), atrie, nid)
                update_delay_list(ld, wl, nid, skel, delays)
            end
        end
        return 0                                    # no change
    else
        tt = PL_new_term_ref(ld)
        if unify_trie(_query_gd(ld), ld, tt, atrie)
            trie_error(ld, rc, tt)
        end
        return 0
    end
end

# PORT: pl-tabling.c update_subsuming_answer
# (pl-tabling.c:5087-5149 at the pin.)
# DIVERGES: the callback of `map_trie_node` gets the trie and a node id and returns `nothing` for `TRIE_MAP_TRUE`; the procedure
# `'$tabling':update/7` is looked up at each call (upstream caches it in `GD->procedures.update7` at the first, `_PL_predicate`);
# the `MSG_TABLING_MODED` debug output does not exist here; `trie_has_children` is the node's `children != 0`.
"Call `'\$tabling':update/7` on the secondary node `nid` and the new moded arguments: keep, replace or done (pl-tabling.c)."
function update_subsuming_answer(
    ld::PL_local_data{T}, ctx::sa_context{T}, nid::Int
)::Union{Nothing, Int} where {T}
    atrie = ctx.atrie
    if (atrie.nodes[nid].flags & TN_SECONDARY) != 0
        gd = _query_gd(ld)
        av = ctx.argv
        agg = av + 5
        action = av + 6
        conditional = answer_is_conditional(gd, atrie, nid) ? 0 : AS_OLD_DEFINED
        PRED_update7 = lookupProcedure(
            mk_sym(T, :update), 7, lookupModule(gd, mk_sym(T, Symbol("\$tabling")))
        )

        if tbl_put_moded_args(ld, atrie, av + 3, nid) &&
            PL_put_integer(ld, av + 0, ctx.flags | conditional) &&
            PL_put_variable(ld, agg) &&
            PL_put_variable(ld, action) &&
            PL_call_predicate(gd, ld, nothing, PL_Q_PASS_EXCEPTION, PRED_update7, av)
            act = PL_get_atom_ex(ld, av + 6)
            act === nothing && return TRIE_MAP_FALSE

            if sym_key(act) == sym_key(mk_sym(T, :done))
                return TRIE_MAP_DONE
            elseif sym_key(act) == sym_key(mk_sym(T, :keep))
                del = 0
            else
                del = nid
            end

            ctx.added = add_subsuming_answer(
                ld, ctx.wl, atrie, ctx.root, ctx.skel, del, agg, ctx.delays
            )
            ctx.added != 0 && return nothing        # TRIE_MAP_TRUE
            return TRIE_MAP_FALSE
        else
            PL_exception(ld, 0) != 0 && return TRIE_MAP_FALSE
            return nothing                          # TRIE_MAP_TRUE
        end
    else
        if atrie.nodes[nid].children == 0           # !trie_has_children(node)
            ctx.garbage += 1
        end
        return nothing                              # TRIE_MAP_TRUE
    end
end

# PORT: pl-tabling.c update_subsuming_answers
# (pl-tabling.c:5150-5206 at the pin.)
# DIVERGES: `wl` is `nothing` and `delays` 0 for monotonic tabling; the functor of the predicate is put as `PL_put_functor` does
# (an atom for arity 0); the monotonic branch's `prune_deleted_mdeps` of a lazy IDG node is TB6's (`IDG` is `nothing` until then).
"Aggregate the new moded arguments `margs` with the secondary nodes below `root`: the added node or 0 (pl-tabling.c)."
function update_subsuming_answers(
    ld::PL_local_data{T}, wl::Union{Nothing, tbl_worklist{T}}, atrie::trie{T}, root::Int,
    skel::term_t, margs::term_t,
    delays::term_t
)::Int where {T}
    gd = _query_gd(ld)
    def = atrie.predicate::Definition{T}
    ctx = sa_context{T}(wl, atrie, root, 0, skel, delays, PL_new_term_refs(ld, 7), 0, 0)

    ok = if def.arity == 0
        PL_put_atom(ld, ctx.argv + 1, def.name)
    else
        PL_put_variable(ld, ctx.argv + 1) &&
            PL_unify_functor(ld, ctx.argv + 1, def.name, def.arity)
    end
    (
        ok && PL_put_atom(ld, ctx.argv + 2, gd.modules[def.module_].atom) &&
        PL_put_term(ld, ctx.argv + 4, margs)
    ) || return 0

    if delays != 0                                  # normal tabling
        if PL_get_nil(ld, delays) && global_delay_list_is_nil(ld)
            ctx.flags = AS_NEW_DEFINED
        end
    else
        ctx.flags = AS_NEW_DEFINED                  # monotonic tabling
    end

    map_trie_node(atrie, root, (tr, n) -> update_subsuming_answer(ld, ctx, n)) ==
    TRIE_MAP_FALSE && return 0

    if ctx.garbage > 10
        if wl !== nothing
            if wl.executing
                wl.needs_answer_gc = true
            else
                prune_answers_worklist(ld, wl)
            end
        else                                        # monotonic tabling
            # (idg = atrie->data.IDG) && idg->lazy: prune_deleted_mdeps(idg), TB6 (`IDG` is `nothing` until then)
            prune_trie(_query_gd(ld), atrie, root, nothing)
        end
    end

    return ctx.added
end

# PORT: pl-tabling.c FUNCTOR_divide2
"The functor `//2` (pl-funct.ih `FUNCTOR_divide2`)."
const FUNCTOR_divide2 = builtin_functor("divide", 2)

# PORT: pl-tabling.c wkl_mode_add_answer
# (pl-tabling.c:5207-5262 at the pin.)
# DIVERGES: the result is the added secondary node or 0; the arguments of `Skel/ModedArgs` are put in `skel` and `margs` with
# `_PL_get_arg` (upstream links the term references to the argument cells, `linkValI`); the `MSG_TABLING_MODED` debug output
# does not exist here.
"Add the moded answer `Skel/ModedArgs` to the moded table `atrie`: the added secondary node or 0 (pl-tabling.c)."
function wkl_mode_add_answer(
    ld::PL_local_data{T}, wl::Union{Nothing, tbl_worklist{T}}, atrie::trie{T},
    answer::term_t, delays::term_t
)::Int where {T}
    av = PL_new_term_refs(ld, 2)
    skel = av + 0
    margs = av + 1

    if PL_is_functor(ld, answer, mk_sym(T, Symbol("/")), 2)
        _PL_get_arg(ld, 1, answer, skel)
        _PL_get_arg(ld, 2, answer, margs)
    else
        PL_error(ld, ERR_DOMAIN, mk_sym(T, :moded_answer), answer)
        return 0
    end

    rc, root = trie_lookup(ld, atrie, 0, -(skel + 1), true, nothing)
    if rc == 1
        rn = atrie.nodes[root]
        if (rn.flags & TN_PRIMARY) != 0
            if (rn.flags & TN_IDG_DELETED) != 0
                rn.flags &= ~TN_IDG_DELETED
                return add_subsuming_answer(ld, wl, atrie, root, skel, 0, margs, delays)
            else
                return update_subsuming_answers(ld, wl, atrie, root, skel, margs, delays)
            end
        else
            set_trie_value_word(_query_gd(ld), atrie, root, ATOM_trienode)
            return add_subsuming_answer(ld, wl, atrie, root, skel, 0, margs, delays)
        end
    else
        trie_error(ld, rc, skel)
        return 0
    end
end

# PORT: pl-tabling.c tbl_unify_answer
# (pl-tabling.c:5458-5477 at the pin.)
# DIVERGES: the trie is an argument (nodes are ids, 0: NULL, the negative dummy solution); `PL_unify_output` is `PL_unify`.
"Unify `term` with the answer node `nid` of `tr`; a secondary node of answer subsumption gives `Ret/ModeArgs` (pl-tabling.c)."
function tbl_unify_answer(
    ld::PL_local_data{T}, tr::trie{T}, nid::Int, term::term_t
)::Bool where {T}
    if nid != 0
        if (tr.nodes[nid].flags & TN_SECONDARY) != 0
            av = PL_new_term_refs(ld, 2)
            rc, parent = unify_trie_term(ld, tr, nid, av + 1)
            rc || return false
            return unify_trie_term(ld, tr, parent, av + 0)[1] &&
                   PL_cons_functor_v(ld, av + 0, FUNCTOR_divide2, av) &&
                   PL_unify(ld, term, av + 0)
        else
            return unify_trie_term(ld, tr, nid, term)[1]
        end
    end

    return true                                     # for negative dummy solutions
end

# PORT: pl-tabling.c set_idg_current
# DIVERGES: the IDG register `ld.tabling.idg_current` is TB6's: it is 0 (none) until TB6 creates it, and then this is refused by
# name, owner TB6.
"Make `atrie` the current IDG node of this thread, `nothing` (NULL) for none (pl-tabling.c)."
function set_idg_current(
    ld::PL_local_data{T}, atrie::Union{Nothing, trie{T}}
)::Bool where {T}
    ld.tabling.idg_current == 0 && return true
    tbl_refuse(T, :set_idg_current, "set_idg_current: the IDG current node register", "TB6")
end

# PORT: pl-tabling.c idg_set_current as pl_idg_set_current2_va
# (pl-tabling.c:8404-8420 at the pin: PRED_IMPL("$idg_set_current", 2, idg_set_current, 0))
# NOTE: a minimal port, owner TB6 supersedes it with the real IDG register. `'\$tbl_leader'/5` (boot/tabling.pl) calls this predicate
# for every tabled call, so TB2's worklists cannot run without it. While the register does not exist (`ld.tabling.idg_current == 0`)
# the upstream `current` is NULL, so `OldCurrent` stays unbound; a register that exists is refused by name, owner TB6 (as
# `set_idg_current`).
"`'\$idg_set_current'(-OldCurrent, +ATrie)`: make `ATrie` the current IDG node and return the old one (pl-tabling.c)."
function pl_idg_set_current2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A2 = PL__t0 + 1
    atrie = get_trie(_query_gd(ld), ld, A2)
    atrie === nothing && return FFALSE

    ld.tabling.idg_current == 0 ||
        tbl_refuse(
            T, :idg_set_current, "\$idg_set_current: the IDG current node register", "TB6"
        )
    return set_idg_current(ld, atrie) ? FTRUE : FFALSE
end

# PORT: pl-tabling.c idg_add_edge as pl_idg_add_edge1_va
# (pl-tabling.c:8386-8400 at the pin: PRED_IMPL("$idg_add_edge", 1, idg_add_edge, 0))
# NOTE: a minimal port, owner TB6 supersedes it with the real IDG register. `tnot/1` and `start_subsumptive_tabling/3` call it.
# While the register does not exist (`ld.tabling.idg_current == 0`) `idg_current()` is NULL and the predicate succeeds; a register
# that exists is refused by name, owner TB6.
"`'\$idg_add_edge'(+ATrie)`: add a child to the current dependency tree (pl-tabling.c)."
function pl_idg_add_edge1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    ld.tabling.idg_current == 0 && return FTRUE         # ctrie = idg_current(): NULL
    tbl_refuse(T, :idg_add_edge, "\$idg_add_edge: the IDG current node register", "TB6")
end

# PORT: pl-tabling.c idg_set_current_wl
"Make the answer trie of the worklist `wlref` the current IDG node (pl-tabling.c)."
function idg_set_current_wl(ld::PL_local_data{T}, wlref::term_t)::Bool where {T}
    wl = get_worklist(ld, wlref)
    wl === nothing && return false

    return set_idg_current(ld, wl_table(ld, wl))
end

# PORT: pl-tabling.c unify_dependency
# (pl-tabling.c:5482-5540 at the pin.)
# DIVERGES: the five arguments of the dependency term are unified with `srcskel` and `a0+1` .. `a0+4` (upstream binds the fresh
# output variables to them, `Trail(p, linkValI(v))`, which is the same unification); `ensureStackSpace` is dropped (the stacks
# grow on demand); `answer` is a node of `wl`'s answer trie (0: NULL, a negative delay); pushing a delay on the global delay
# list is TB4's `push_delay_list` / `tbl_push_delay` (the delay element is built with the FLI from the table symbol).
"Unify `a0..a0+4` with the dependency `dependency(SrcSkel, Cont, TargetSkel, TargetWL, Delays)` and the answer (pl-tabling.c)."
function unify_dependency(
    ld::PL_local_data{T}, a0::term_t, dependency::term_t, wl::tbl_worklist{T}, answer::Int,
    unified::Bool
)::Bool where {T}
    srcskel = PL_new_term_ref(ld)
    a = PL_new_term_ref(ld)

    _PL_get_arg(ld, 1, dependency, a) || return false   # if ( unlikely(!isTerm(*dp)) ) return false
    PL_unify(ld, srcskel, a) || return false            # SrcSkeleton
    for i in 1:4                                        # Continuation, TargetSkeleton, TargetWL, Delays
        (_PL_get_arg(ld, i + 1, dependency, a) && PL_unify(ld, a0 + i, a)) || return false
    end

    if unified || answer == 0
        PL_unify(ld, srcskel, a0 + 0) || return false
    else                                                # unify the answer into the skeleton
        (
            tbl_unify_answer(ld, wl_table(ld, wl), answer, srcskel) &&
            PL_unify(ld, a0 + 0, srcskel)
        ) || return false
    end

    idg_set_current_wl(ld, a0 + 3) || return false

    gd = _query_gd(ld)
    atrie = wl_table(ld, wl)
    if answer == 0                                      # negative delay
        h = PL_new_term_ref(ld)
        ld.slots[h + 1] = trie_symbol(gd, atrie)        # p[1] = wl->table->symbol
        push_delay_list(ld, h)
    elseif answer_is_conditional(gd, atrie, answer)
        tbl_push_delay(ld, trie_symbol(gd, atrie), atrie, a0 + 0, answer)   # atrie+Data, Data = delay_to_data(answer, a0+0)
    end

    return true
end

# PORT: pl-tabling.c tbl_put_moded_args
# (pl-tabling.c:5542-5554 at the pin.)
# DIVERGES: the trie is an argument; node 0 (the negative dummy solution) puts the reserved `trienode` (as `$tbl_trienode/1`).
"Put the moded arguments of the answer node `nid` of `tr` in `t` (pl-tabling.c)."
function tbl_put_moded_args(
    ld::PL_local_data{T}, tr::trie{T}, t::term_t, nid::Int
)::Bool where {T}
    if nid != 0
        if (tr.nodes[nid].flags & TN_SECONDARY) != 0
            return unify_trie_term(ld, tr, nid, t)[1]
        else
            return put_trie_value(ld, tr, t, nid)   # TBD: Can become ATOM_trienode
        end
    else                                            # negative dummy solution
        return PL_put_atom(ld, t, mk_reserved_symbol(T, :trienode))
    end
end

# PORT: pl-tabling.c tbl_single_answer
# (pl-tabling.c:6269-6279 at the pin.) The condition `atrie->data.IDG &&` is copied as is: `IDG` is `nothing` until TB6, so the
# result is 0 until then.
# DIVERGES: the result is a node id (0: NULL); `!atrie->clause` is `clause == 0` (the clause atom word, TR4).
"The answer node of the complete table `atrie` if it has a single unconditional answer and needs no compiled clause, else 0 (pl-tabling.c)."
function tbl_single_answer(atrie::trie{T})::Int where {T}
    if atrie.value_count == 1 &&
        atrie.IDG !== nothing &&
        atrie.clause == 0 &&
        atrie.worklist === nothing &&           # no conditional answers
        (atrie.flags & (TRIE_ISSHARED | TRIE_ISMAP)) == 0
        return trie_single_value_node(atrie)
    end

    return 0
end

# PORT: pl-tabling.c FUNCTOR_comma2
"The functor `,/2` (pl-funct.ih `FUNCTOR_comma2`)."
const FUNCTOR_comma2 = builtin_functor("comma", 2)

# PORT: pl-tabling.c FUNCTOR_semicolon2
"The functor `;/2` (pl-funct.ih `FUNCTOR_semicolon2`)."
const FUNCTOR_semicolon2 = builtin_functor("semicolon", 2)

# PORT: pl-tabling.c put_delay_set
# (pl-tabling.c:6952-7062 at the pin; the pin's `answer_ctx` is its one field, the skeleton `skel`.)
# DIVERGES: the trie `tr` of the answer is an argument (upstream reads it from the nodes; it holds the variable-sharing records,
# `record_of_value`); `top` is a 1-based index into the set's delays (`get_delay_set`), a delay's trie is `gd.tries[d.variant]`
# and its call variant the node `at.variant` of the variant table (`top->variant->data.variant`); a DELETED delay keeps the
# answer as `answer_ref(serial, nid)` (`propagate_to_answer` writes it: the trie is gone with
# `variant`), decoded here for `is_ground_trie_node`; `PL_get_arg(1, ans, tmp)` is `_PL_get_arg` (the term is the `Ret/ModeArgs`
# compound `tbl_unify_answer` made); the error line "OOPS! could not find variant table" is `return false` (no DEBUG output).
"Build the condition of the delay set `set` of `di` (answer of `tr`) in `cond`: the conjunction of its delays; `skel` is the answer's skeleton (pl-tabling.c)."
function put_delay_set(
    ld::PL_local_data{T}, cond::term_t, tr::trie{T}, di::delay_info, set::delay_set,
    skel::term_t
)::Bool where {T}
    gd = _query_gd(ld)
    av = PL_new_term_refs(ld, 6)
    count = 0
    gshare = 0
    gskel = 0
    arity = 0
    tmp = av + 4
    ret = av + 5
    tnot1 = lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :tnot)), 1)

    ds = get_delay_set(di, set)                         # get_delay_set(di, set, &base, &top)
    top = length(ds)                                    # the 1-based index of top[-1]

    # Get the variable sharing term
    if top > 0 && ds[top].answer != 0 && ds[top].variant == 0
        @assert IS_REC_DELAY(ds[top].answer)
        r = record_of_value(tr, word(UNREC_DELAY(ds[top].answer)) << 2)
        gshare = PL_new_term_refs(ld, 2)
        PL_recorded(ld, r, gshare) || return false
        na = PL_get_name_arity(ld, gshare)
        arity = na === nothing ? 0 : na[2]
        gskel = gshare + 1
        _PL_get_arg(ld, 1, gshare, gskel)
        PL_unify(ld, gskel, skel) || return false      # "global skeleton doesn't unify"
        top -= 1
    end

    while top >= 1                                      # for(--top; top >= base; top--)
        d = ds[top]
        top -= 1
        c1 = count == 0 ? cond : av + 0

        if d.variant == DV_DELETED
            if d.answer != 0
                at = gd.tries[answer_ref_trie(d.answer)]
                is_ground_trie_node(at, answer_ref_node(d.answer)) || (arity -= 1)
            end
            continue
        end
        if d.answer != 0                                # positive delay
            at = gd.tries[d.variant]
            ans = av + 1

            PL_put_variable(ld, c1)
            PL_put_variable(ld, ans)
            PL_put_variable(ld, ret)

            at.variant == 0 && return false             # NULL top->variant->data.variant
            unify_trie_term(
                ld, variant_table(ld, (at.flags & TRIE_ISSHARED) != 0), at.variant, c1
            )[1] || return false
            get_answer_table(ld, nothing, c1, ret, 0) === nothing && return false      # "could not find variant table"

            if (at.nodes[d.answer].flags & TN_SECONDARY) != 0       # Ret/ModeArgs
                tbl_unify_answer(ld, at, d.answer, ans) || return false
                _PL_get_arg(ld, 1, ans, tmp)
                PL_unify(ld, tmp, ret) || return false
                _PL_get_arg(ld, 2, ans, tmp)
                PL_cons_functor(ld, c1, FUNCTOR_divide2, c1, tmp) || return false
                uans = ans
            else
                unify_trie_term(ld, at, d.answer, ret)[1] || return false
                uans = ret
            end

            if !is_ground_trie_node(at, d.answer)
                @assert gshare != 0
                _PL_get_arg(ld, arity, gshare, gskel)
                PL_unify(ld, gskel, uans) || return false       # "skeleton does not unify"
                arity -= 1
            end
        else                                            # negative delay
            at = gd.tries[d.variant]
            PL_put_variable(ld, c1)
            at.variant == 0 && return false
            unify_trie_term(
                ld, variant_table(ld, (at.flags & TRIE_ISSHARED) != 0), at.variant, c1
            )[1] || return false
            PL_cons_functor(ld, c1, tnot1, c1) || return false
        end

        if count > 0                                    # count++ > 0
            PL_cons_functor(ld, cond, FUNCTOR_comma2, c1, cond) || return false
        end
        count += 1
    end

    PL_reset_term_refs(ld, av)

    return true
end

# PORT: pl-tabling.c unify_delay_info
# (pl-tabling.c:7061-7097 at the pin.)
# DIVERGES: the trie is an argument (nodes are ids); the context `answer_ctx` is its one field, the skeleton `skel`. An answer is
# named as TB4 names it, `answer_ref(serial, nid)` = `serial << 32 | nid` (dispatcher decision; upstream: the `trie_node *`):
# `answer_delay_info(NULL, answer, false)` is TB4's `node_delayinfo(gd, tr, nid)`, keyed by it, read only when the node has
# `TN_DELAYINFO` (only TB4 sets it). A delay list is `put_delay_set`'s (above), one conjunction at a time, joined by `;`.
"Unify `t` with the condition of the answer node `nid` of `tr`: `true` for an unconditional answer (pl-tabling.c)."
function unify_delay_info(
    ld::PL_local_data{T}, t::term_t, tr::trie{T}, nid::Int, skel::term_t
)::Bool where {T}
    di = if (tr.nodes[nid].flags & TN_DELAYINFO) != 0
        node_delayinfo(_query_gd(ld), tr, nid)
    else
        nothing
    end
    if di !== nothing
        if DL_IS_DELAY_LIST(di)
            av = PL_new_term_refs(ld, 2)
            cond = av + 1
            count = 0
            for set in delay_sets(di)                   # delay_sets(di, &base, &top); for(; base < top; base++)
                c1 = count == 0 ? cond : av + 0
                isempty(di.delay_sets) && continue      # isEmptyBuffer(&di->delay_sets)
                put_delay_set(ld, c1, tr, di, set, skel) || return false
                if count > 0                            # count++ > 0
                    PL_cons_functor_v(ld, cond, FUNCTOR_semicolon2, av) || return false
                end
                count += 1
            end

            return PL_unify(ld, t, cond)
        else
            return PL_unify_atom(ld, t, mk_sym(T, :undefined))
        end
    else
        return PL_unify_atom(ld, t, mk_sym(T, Symbol("true")))
    end
end

# ORIGINAL (TAB1 TB3): the `data_kind` of TR2's `trie_gen` / `trie_gen_raw` that selects `unify_delay_info` (upstream passes the
# function pointer `unify_delay_info` as `unify_data`; TR2 has kind 0, no data, and 1, `unify_node_id`'s handle, whose
# encoding `trie_node_handle` = `serial << 32 | nid` is TB4's `answer_ref`: an answer handed to Prolog is that integer).
# STACK EDIT (TR2, done): trie_gen_raw's data step is `trie_gen_unify_data` (src/pl-trie.jl), whose DELAY_INFO arm calls
# `unify_delay_info(ld, Data, trs, nid, st.key)`.
"`trie_gen` data kind: unify `Data` with the condition of the answer (pl-tabling.c `unify_delay_info` as `unify_data`)."
const TRIE_GEN_DELAY_INFO = 2

# PORT: pl-tabling.c tbl_answer as pl_tbl_answer3_va
# (PRED_IMPL("$tbl_answer", 3, tbl_answer, PL_FA_NONDETERMINISTIC), pl-tabling.c:7114-7123 at the pin.)
# DIVERGES: `ctx.skel = A2` is the key TR2's `trie_gen_raw` holds (`st.key`, see `TRIE_GEN_DELAY_INFO`).
"`'\$tbl_answer'(+Trie, ?Skeleton, -Condition)`: the answers of the table `Trie` with their condition (pl-tabling.c)."
function pl_tbl_answer3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    A2 = PL__t0 + 1
    A3 = PL__t0 + 2

    return trie_gen(_query_gd(ld), ld, A1, 0, A2, 0, A3, TRIE_GEN_DELAY_INFO, PL__ctx)
end

# PORT: pl-tabling.c tbl_answer_c as pl_tbl_answer_c4_va
# (PRED_IMPL("$tbl_answer_c", 4, tbl_answer_c, PL_FA_NONDETERMINISTIC), pl-tabling.c:7125-7157 at the pin.)
# DIVERGES: a redo or a cut goes to TR2's `trie_gen_raw` with no trie (its state holds the trie and the root: upstream looks the
# root up again on a redo and `trie_gen_raw` then ignores it; on a cut `clear_trie_gen_state` is `trie_gen_raw`'s `FRG_CUTTED`);
# the condition's skeleton is `Key` (A3, see `TRIE_GEN_DELAY_INFO`; upstream `ctx.skel = A2`): it is read only by `put_delay_set`,
# TB4's, which needs A2 here.
"`'\$tbl_answer_c'(+Trie, +Skeleton, -ModedArgs, -Condition)`: the moded arguments of `Skeleton` in the moded table `Trie` (pl-tabling.c)."
function pl_tbl_answer_c4_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    A2 = PL__t0 + 1
    A3 = PL__t0 + 2
    A4 = PL__t0 + 3

    if PL_foreign_control(PL__ctx) != FRG_FIRST_CALL   # FRG_CUTTED: clear_trie_gen_state(CTX_PTR); FRG_REDO
        return trie_gen_raw(ld, nothing, 0, A3, 0, A4, TRIE_GEN_DELAY_INFO, PL__ctx)
    end

    tr = get_trie_nodes(_query_gd(ld), ld, A1)
    if tr !== nothing
        rc, root = trie_lookup(ld, tr, 0, -(A2 + 1), false, nothing)
        if rc == 1
            return trie_gen_raw(ld, tr, root, A3, 0, A4, TRIE_GEN_DELAY_INFO, PL__ctx)
        else
            return trie_error(ld, rc, A1) ? FTRUE : FFALSE
        end
    end

    return FFALSE
end

# ORIGINAL (TAB1 TB3 stack hole, gate 12): the `data_kind` of TR2's `trie_gen` / `trie_gen_raw` that selects `unify_delay_info_dl`
# (upstream passes the function pointer as `unify_data`). `'$tbl_answer_dl'/3,4` is `tnot/1`'s test of an answer's condition; it is
# called by TB5's `tnot` and later steps, ported here because TB4's tests run `tnot/1`.
# STACK EDIT (TR2, done): `trie_gen_unify_data` (src/pl-trie.jl) has the arm for kind 3.
"`trie_gen` data kind: unify `Data` with the kind of the answer, `true`, a handle or `nonground` (pl-tabling.c `unify_delay_info_dl`)."
const TRIE_GEN_DELAY_INFO_DL = 3

# PORT: pl-tabling.c unify_delay_info_dl
# (pl-tabling.c:7158-7176 at the pin.)
# DIVERGES: the answer is its trie `tr` and node id `nid`; a ground conditional answer is named by its handle `trie_node_handle`
# (upstream: `PL_unify_pointer(t, answer)`).
"Unify `t` with `true` for an unconditional answer, its handle for a conditional ground one, else `nonground`; false for a deleted answer (pl-tabling.c)."
function unify_delay_info_dl(
    ld::PL_local_data{T}, t::term_t, tr::trie{T}, nid::Int
)::Bool where {T}
    if (tr.nodes[nid].flags & (TN_IDG_DELETED | TN_IDG_ADDED)) == TN_IDG_DELETED
        return false
    end

    if answer_is_conditional(_query_gd(ld), tr, nid)
        if is_ground_trie_node(tr, nid)
            return PL_unify_int64(ld, t, trie_node_handle(tr, nid))
        else
            return PL_unify_atom(ld, t, mk_sym(T, :nonground))
        end
    else
        return PL_unify_atom(ld, t, mk_sym(T, Symbol("true")))
    end
end

# PORT: pl-tabling.c tbl_answer_dl as pl_tbl_answer_dl3_va
# (PRED_IMPL("$tbl_answer_dl", 3, tbl_answer_dl, PL_FA_NONDETERMINISTIC), pl-tabling.c:7177-7181 at the pin.)
"`'\$tbl_answer_dl'(+ATrie, ?Skeleton, -Kind)`: the answers of `ATrie` with their kind (`true`, a handle, `nonground`) (pl-tabling.c)."
function pl_tbl_answer_dl3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    A2 = PL__t0 + 1
    A3 = PL__t0 + 2

    return trie_gen(_query_gd(ld), ld, A1, 0, A2, 0, A3, TRIE_GEN_DELAY_INFO_DL, PL__ctx)
end

# PORT: pl-tabling.c tbl_answer_dl as pl_tbl_answer_dl4_va
# (PRED_IMPL("$tbl_answer_dl", 4, tbl_answer_dl, PL_FA_NONDETERMINISTIC), pl-tabling.c:7183-7212 at the pin.)
# DIVERGES: as pl_tbl_answer_c4_va: a redo or a cut goes to TR2's `trie_gen_raw` with no trie.
"`'\$tbl_answer_dl'(+ATrie, +Skeleton, -Subsuming, -Kind)`: the answers below `Skeleton` with their kind (pl-tabling.c)."
function pl_tbl_answer_dl4_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    A2 = PL__t0 + 1
    A3 = PL__t0 + 2
    A4 = PL__t0 + 3

    if PL_foreign_control(PL__ctx) != FRG_FIRST_CALL   # FRG_CUTTED: clear_trie_gen_state(CTX_PTR); FRG_REDO
        return trie_gen_raw(ld, nothing, 0, A3, 0, A4, TRIE_GEN_DELAY_INFO_DL, PL__ctx)
    end

    tr = get_trie_nodes(_query_gd(ld), ld, A1)
    if tr !== nothing
        rc, root = trie_lookup(ld, tr, 0, -(A2 + 1), false, nothing)
        if rc == 1
            return trie_gen_raw(ld, tr, root, A3, 0, A4, TRIE_GEN_DELAY_INFO_DL, PL__ctx)
        else
            return trie_error(ld, rc, A1) ? FTRUE : FFALSE
        end
    end

    return FFALSE
end

# ---- TB3b: S_TABLED support, the complete-table fast path (pl-tabling.c:12229-12636 at 18168e62) ----
# ORIGINAL (TAB1 TB3b): frame arguments are local-stack slots: argument `n` (0-based) of frame `fr` is `ld.slots[argFrameP(base,
# n) + 1]`, its location `-(argFrameP(base, n) + 1)` (as a term reference `t` is `ld.slots[t + 1]`, location `-(t + 1)`). A slot is
# never an unbound variable (TB1's `unify_trie_ret`): upstream's "unbound on the local stack" branches (`onStack(local, ...)`,
# `LTrail`) have nothing to globalise here. The supervisor frame is an argument (upstream reads `LD->query->registers.fr`, saved by
# `SAVE_REGISTERS`). TR4 interfaces used (see evidence/TB3/handoff2.md): `compile_trie(gd, ld, def, tr)::word`,
# `trie_maybe_discard_nodes(tr)`, `gd.procedures_trie_gen_compiled2`.

"The slot index of argument `n` (0-based) of frame `fr` (pl-incl.h `argFrameP(fr, n)`)."
@inline _frame_arg_slot(ld::PL_local_data, fr::Int, n::Int)::Int =
    argFrameP(ld.frames[fr].base, n) + 1

# PORT: pl-tabling.c put_supervisor_goal
# (pl-tabling.c:12236-12278 at the pin.)
# DIVERGES: the frame is an argument; `M:Head` is built with the FLI (`PL_unify_functor`, the argument links of
# `put_frame_goal`, `PL_cons_functor` with `:/2`), upstream writes the cells in one allocation (`allocGlobalNoShift`):
# the same term. `ensureStackSpace` is dropped (the stacks grow on demand).
"Put `M:Head` for the call in the supervisor frame `fr` in `t`; with `abstract` the arguments are fresh variables (pl-tabling.c)."
function put_supervisor_goal(
    ld::PL_local_data{T}, t::term_t, def::Definition{T}, fr::Int, abstract::Bool
)::Bool where {T}
    gd = _query_gd(ld)
    arity = def.arity
    goal = PL_new_term_ref(ld)

    PL_unify_functor(ld, goal, def.name, arity) || return false   # gp[2] = def->functor->name / consCompound(&gp[3])
    if arity > 0 && !abstract
        argv = argFrameP(ld.frames[fr].base, 0)     # Word fp = argFrameP(LD->query->registers.fr, 0)
        _, gw, _ = _deref_loc(ld, -(goal + 1))
        argp = valPtr(gw)
        for i in 1:arity
            _cell_link!(ld, argp + i, argv + i)     # *ap = needsRef(*fa) ? makeRefG(fa) : *fa
        end
    end

    m = PL_new_term_ref(ld)
    PL_put_atom(ld, m, gd.modules[def.module_].atom) || return false   # gp[1] = def->module->name
    colon2 = lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :(:))), 2)
    PL_cons_functor(ld, goal, colon2, m, goal) || return false         # gp[0] = FUNCTOR_colon2

    return PL_put_term(ld, t, goal)                 # *valTermRef(t) = consCompound(gp)
end

# PORT: pl-tabling.c complete_answer_clause
# (pl-tabling.c:12287-12319 at the pin.)
# DIVERGES: the result is an atom word (0: none); the `O_PLMT` shared branch is TH1's (a private table only here: the shared
# tables are refused where they are made, `get_answer_table`).
"The compiled answer trie of the complete, valid table `atrie`, or 0 if `start_tabling/3` must handle the call (pl-tabling.c)."
function complete_answer_clause(ld::PL_local_data{T}, atrie::trie{T})::word where {T}
    gd = _query_gd(ld)
    if (atrie.flags & TRIE_COMPLETE) == 0 ||
        sym_key(complete_or_invalid_status(ld, atrie, true)) != sym_key(mk_sym(T, :complete))
        return word(0)
    end

    clref = atrie.clause
    if clref == 0
        def = gd.procedures_trie_gen_compiled2.definition::Definition{T}
        tbl_single_answer(atrie) != 0 && return trie_symbol(gd, atrie)
        clref = compile_trie(gd, ld, def, atrie)
        clref == _atom_word!(ld, mk_sym(T, :error)) && return clref
    end
    trie_maybe_discard_nodes(_query_gd(ld), atrie)

    return clref
end

# PORT: pl-tabling.c call_complete_table
# (pl-tabling.c:12321-12339 at the pin.)
# DIVERGES: `idg_init_variant` and `idg_add_edge` are TB6's: both do nothing for a table that has no IDG node and whose
# predicate is neither incremental nor monotonic (pl-tabling.c:8296, :8369), the only tables here; else refused by name.
# `O_TRIE_STATS` is on: `gen_call` counts the private table.
"Register calling the complete table `atrie` and return `clref`, `fail` or `error` (atom words, pl-tabling.c)."
function call_complete_table(
    ld::PL_local_data{T}, atrie::trie{T}, def::Definition{T}, clref::word
)::word where {T}
    if atrie.IDG !== nothing || (
        def.tabling !== nothing &&
        (def.tabling.flags & (TP_MONOTONIC | TP_INCREMENTAL)) != 0
    )
        tbl_refuse(
            T,
            :idg_init_variant,
            "call_complete_table: an incremental or monotonic table (idg_init_variant, idg_add_edge)",
            "TB6"
        )
    end
    atrie.gen_call += 1                             # atrie->stats.gen_call++

    return clref
end

# PORT: pl-tabling.c flat_skeleton
# (pl-tabling.c:12455-12482 at the pin.)
# DIVERGES: `vars` holds the global positions of the variable cells (see the TB3b note: none is on the local stack).
"The word of `ret(V1, ...)` for the variables `vars` found by `trie_lookup_flat`; the atom `ret` if there are none (pl-tabling.c)."
function flat_skeleton(ld::PL_local_data{T}, vars::Vector{Int})::word where {T}
    arity = length(vars)
    arity == 0 && return _atom_word!(ld, mk_sym(T, :ret))

    p = _alloc_compound!(ld, ret_functor(ld, arity), arity)
    for (i, vp) in enumerate(vars)
        @assert vp > 0 "flat_skeleton: a variable cell on the local stack"
        ld.gstack[p + i] = makeRefG(vp)             # *p = makeRefG(vp)
    end

    return consPtr(p, TAG_COMPOUND | STG_GLOBAL)
end

# PORT: pl-tabling.c tbl_complete_answer_clause
# (pl-tabling.c:12484-12565 at the pin.)
# DIVERGES: the supervisor frame `fr` is an argument; the result is an atom word (0: none); the variables of the flat lookup are a
# vector; `hasStackSpace` is true (the stacks grow on demand); `inner_is_monotonic` is TB7's (refused by name for a monotonic
# predicate outside assert propagation); the `O_PLMT` `shared` is false.
"The fast path of `S_TABLED` for the variant tabled `def` called in frame `fr`: a clause reference, `fail`, `error` or 0 (pl-tabling.c)."
function tbl_complete_answer_clause(
    ld::PL_local_data{T}, def::Definition{T}, fr::Int
)::word where {T}
    gd = _query_gd(ld)
    tp = def.tabling::table_props
    arity = def.arity
    shared = false

    if (tp.flags & TP_MONOTONIC) != 0
        ld.tabling.in_assert_propagation && return word(0)  # must shift/1 the dependency
        tbl_refuse(
            T,
            :inner_is_monotonic,
            "tbl_complete_answer_clause: a monotonic predicate (inner_is_monotonic)",
            "TB7"
        )
    end

    variants = variant_table(ld, shared)

    id = start_node_id(gd, tp)
    start = get_start_node(start_node_array(ld, shared), id)
    cached = start != 0
    vars = Int[]
    argv = Int[-_frame_arg_slot(ld, fr, i - 1) for i in 1:arity]   # argFrameP(fr, 0)

    rc, start, node = trie_lookup_flat(gd, ld, variants, start, def, argv, vars)
    if !cached && start != 0
        set_start_node(ld, variants, id, start)
    end
    if rc != TRIE_LOOKUP_NOT_FLAT
        clref = word(0)
        if rc == 1 && variants.nodes[node].value != 0 &&
            (
                clref = complete_answer_clause(
                    ld, value_trie(gd, variants.nodes[node].value)
                )
            ) != 0
            atrie = value_trie(gd, variants.nodes[node].value)
            skel = flat_skeleton(ld, vars)
            clref = call_complete_table(ld, atrie, def, clref)
            if clref != _atom_word!(ld, mk_sym(T, :fail)) &&
                clref != _atom_word!(ld, mk_sym(T, :error))
                ld.slots[_frame_arg_slot(ld, fr, 0)] = clref   # *argFrameP(fr, 0) = atom2word(clref)
                ld.slots[_frame_arg_slot(ld, fr, 1)] = skel    # *argFrameP(fr, 1) = skel
            end
        end
        return clref
    end

    return complete_answer_clause_term(ld, def, fr, variants)
end

# PORT: pl-tabling.c complete_answer_clause_term
# (pl-tabling.c:12567-12636 at the pin.)
# DIVERGES: as `tbl_complete_answer_clause`; the `retry` after a global stack overflow (`makeMoreStackSpace`) is dropped
# (`unify_trie_ret` is a Bool: the stacks grow on demand); `deRef(sp); w = *sp` is `_slot_link!` of the skeleton onto itself.
"The slow path of `tbl_complete_answer_clause`: look up `M:Head` with `trie_lookup_abstract` (pl-tabling.c)."
function complete_answer_clause_term(
    ld::PL_local_data{T}, def::Definition{T}, fr::Int, variants::trie{T}
)::word where {T}
    gd = _query_gd(ld)
    clref = word(0)
    error = _atom_word!(ld, mk_sym(T, :error))

    fid = PL_open_foreign_frame(ld)
    variant = PL_new_term_ref(ld)
    skel = PL_new_term_ref(ld)
    if !put_supervisor_goal(ld, variant, def, fr, false)
        clref = error
        @goto out
    end
    sz = pred_max_table_subgoal_size(ld, def)
    sa = size_abstract(2, sz == -1 ? typemax(Int) : sz)
    vars = Int[]

    rc, node = trie_lookup_abstract(ld, variants, 0, -(variant + 1), false, sa, vars)
    (rc != 1 || variants.nodes[node].value == 0) && @goto out   # new, abstracted or error
    atrie = value_trie(gd, variants.nodes[node].value)
    (clref = complete_answer_clause(ld, atrie)) == 0 && @goto out

    if isempty(vars)
        PL_put_atom(ld, skel, mk_sym(T, :ret))
    elseif !unify_trie_ret(ld, skel, vars)
        clref = error
        @goto out
    end

    clref = call_complete_table(ld, atrie, def, clref)
    if clref != _atom_word!(ld, mk_sym(T, :fail)) && clref != error
        _slot_link!(ld, skel + 1, skel + 1)         # deRef(sp)
        w = ld.slots[skel + 1]                      # w = *sp
        PL_close_foreign_frame(ld, fid)             # frame args may overlap fid
        ld.slots[_frame_arg_slot(ld, fr, 0)] = clref
        ld.slots[_frame_arg_slot(ld, fr, 1)] = w
        return clref
    end

    @label out
    PL_close_foreign_frame(ld, fid)
    return clref
end

# =====================================================================================================================
# TAB1 TB4: WFS and delays (pl-tabling.c :290-330 and :960-2560 at swipl-devel 18168e629eab)
# REPRESENTATION (DIVERGES, representation-only; docs/architecture.md "TAB1 TB4"):
# - an answer is named by its trie and its node id. The key of `gd.tabling_answer_delay_infos` and an entry of
#   `worklist.pos_undefined` are `answer_ref(serial, nid)` = `serial << 32 | nid` (upstream: the `trie_node *`, unique).
# - `delay.variant` and `delay_info.variant` are the ANSWER TRIE's serial in `gd.tries` (upstream: the answer trie, resp. the
#   variant-table node whose value is that trie); `worklist.delays` holds `delay(serial, nid)` of the conditional answers
#   that depend on the worklist's table (upstream: their `trie_node *`).
# - `DL_UNDEFINED` is the delay_info `DL_UNDEFINED_INFO`, compared by identity (upstream `(delay_info*)0x1`).
# - a variable-sharing record (`REC_DELAY`) is a slot of the owning answer trie's `records` (TR1's `new_record_value!`); its
#   delay is `delay(0, -slot)` (upstream: the record pointer with bit 0 set, and a NULL variant).
# - `delay_set.offset` counts the delays before the set (0-based as upstream); the set's delays are `offset+1:offset+size`.
# - the term walks use the FLI (`PL_get_list`, `_PL_get_arg`, `trie_deref`) where upstream walks the words; the
#   `ensureGlobalSpace` + `retry` of update_delay_list_any is dropped (the FLI calls allocate as they go).
# =====================================================================================================================

# ORIGINAL: the name of an answer in the kernel (upstream: the `trie_node *`).
"The reference of answer node `nid` of the answer trie with serial `serial` (`serial << 32 | nid`)."
@inline answer_ref(serial::Int, nid::Int)::Int = (serial << 32) | nid
"The trie serial of the answer reference `r`."
@inline answer_ref_trie(r::Int)::Int = r >> 32
"The node id of the answer reference `r`."
@inline answer_ref_node(r::Int)::Int = r & 0xffffffff

# PORT: pl-tabling.c DL_UNDEFINED as DL_UNDEFINED_INFO
# DIVERGES: an identity sentinel delay_info (upstream `(delay_info*)0x1`); TB0's integer `DL_UNDEFINED` stays for its readers.
# The delay info of an answer that is undefined (pl-tabling.c `DL_UNDEFINED`). A comment, not a docstring: a docstring on a
# `const` leaves a `#…#val` temporary holding the object, which tools/lint_globals.jl reports as a second non-const global.
const DL_UNDEFINED_INFO = delay_info(-1, UInt32(0), delay_set[], delay[])
# PORT: pl-tabling.c DL_IS_DELAY_LIST
"Whether `di` is a delay list: neither NULL nor `DL_UNDEFINED_INFO` (pl-tabling.c `DL_IS_DELAY_LIST`)."
DL_IS_DELAY_LIST(di::Union{Nothing, delay_info})::Bool =
    di !== nothing && di !== DL_UNDEFINED_INFO

# PORT: pl-tabling.c node_delayinfo
# (pl-tabling.c:307 at the pin)
# DIVERGES: the node is its trie and id; the table key is `answer_ref`.
"The delay info of answer `nid` of `atrie` (pl-tabling.c): `nothing` unless the node has `TN_DELAYINFO`."
function node_delayinfo(
    gd::PL_global_data{T}, atrie::trie{T}, nid::Int
)::Union{Nothing, delay_info} where {T}
    if (atrie.nodes[nid].flags & TN_DELAYINFO) != 0
        return get(gd.tabling_answer_delay_infos, answer_ref(atrie.serial, nid), nothing)
    end
    return nothing
end

# PORT: pl-tabling.c set_node_delayinfo
# (pl-tabling.c:317 at the pin)
"Set (`di`) or remove (`nothing`) the delay info of answer `nid` of `atrie` and its flag `TN_DELAYINFO` (pl-tabling.c)."
function set_node_delayinfo(
    gd::PL_global_data{T}, atrie::trie{T}, nid::Int, di::Union{Nothing, delay_info}
)::Nothing where {T}
    n = atrie.nodes[nid]
    if di !== nothing
        gd.tabling_answer_delay_infos[answer_ref(atrie.serial, nid)] = di
        n.flags |= TN_DELAYINFO
    elseif (n.flags & TN_DELAYINFO) != 0
        n.flags &= ~TN_DELAYINFO
        delete!(gd.tabling_answer_delay_infos, answer_ref(atrie.serial, nid))
    end
    return nothing
end

# PORT: pl-tabling.c REC_DELAY
# (pl-tabling.c:966 at the pin)
# DIVERGES: a record is a slot of the owning answer trie's `records`; the delay's answer is the slot negated.
"The delay answer of the variable-sharing record in slot `slot` (pl-tabling.c `REC_DELAY`)."
REC_DELAY(slot::Int)::Int = -slot
# PORT: pl-tabling.c UNREC_DELAY
# (pl-tabling.c:970 at the pin)
"The record slot of the delay answer `a` (pl-tabling.c `UNREC_DELAY`)."
UNREC_DELAY(a::Int)::Int = -a
# PORT: pl-tabling.c IS_REC_DELAY
# (pl-tabling.c:974 at the pin)
"Whether the delay answer `a` is a variable-sharing record (pl-tabling.c `IS_REC_DELAY`)."
IS_REC_DELAY(a::Int)::Bool = a < 0

# PORT: pl-tabling.c answer_is_conditional
# (pl-tabling.c:982 at the pin)
"Whether answer `nid` of `atrie` is conditional: undefined or with a delay set (pl-tabling.c)."
function answer_is_conditional(
    gd::PL_global_data{T}, atrie::trie{T}, nid::Int
)::Bool where {T}
    di = node_delayinfo(gd, atrie, nid)
    return di !== nothing && (di === DL_UNDEFINED_INFO || !isempty(di.delay_sets))
end

# PORT: pl-tabling.c answer_delay_info
# (pl-tabling.c:990 at the pin)
# DIVERGES: `atrie` is `wl`'s answer trie (an argument); `di.variant` is its serial (upstream `wl->table->data.variant`).
"The delay info of answer `nid` of `wl`'s table; a new one if `create` (pl-tabling.c)."
function answer_delay_info(
    gd::PL_global_data{T}, wl::tbl_worklist{T}, atrie::trie{T}, nid::Int, create::Bool
)::Union{Nothing, delay_info} where {T}
    di = node_delayinfo(gd, atrie, nid)
    if di !== nothing
        return di
    elseif !create
        return nothing
    else
        di = delay_info(wl.table, UInt32(0), delay_set[], delay[])
        set_node_delayinfo(gd, atrie, nid, di)
        wl.undefined += 1
        return di
    end
end

# PORT: pl-tabling.c delete_answer
# (pl-tabling.c:1021 at the pin)
"Remove the answer `nid` of the trie with serial `serial` from the answer buffer `ab` (pl-tabling.c)."
function delete_answer(ab::Vector{delay}, serial::Int, nid::Int)::Nothing
    filter!(d -> !(d.variant == serial && d.answer == nid), ab)
    return nothing
end

# PORT: pl-tabling.c destroy_delay_info
# (pl-tabling.c:1035 at the pin)
"Remove and free the delay info of answer `nid` of `atrie`; if `propagate`, also its entries in the worklists' `delays` (pl-tabling.c)."
function destroy_delay_info(
    gd::PL_global_data{T}, atrie::trie{T}, nid::Int, propagate::Bool
)::Nothing where {T}
    di = node_delayinfo(gd, atrie, nid)
    if DL_IS_DELAY_LIST(di)
        set_node_delayinfo(gd, atrie, nid, nothing)
        if di.has_share_records != 0
            for d in di.delays                                  # keep a flag to see whether we have these
                IS_REC_DELAY(d.answer) &&
                    erase_value!(atrie, word(UNREC_DELAY(d.answer)) << 2)
            end
        end
        if propagate
            for d in di.delays
                at = d.variant
                if at != 0 && at != DV_DELETED
                    wl = gd.tries[at].worklist
                    if wl isa worklist && !isempty(wl.delays)
                        delete_answer(wl.delays, atrie.serial, nid)
                    end
                end
            end
        end
        empty!(di.delay_sets)
        empty!(di.delays)
    end
    return nothing
end

# PORT: pl-tabling.c answer_set_general_undefined
# (pl-tabling.c:1088 at the pin)
"Make answer `nid` of `atrie` undefined without conditions (pl-tabling.c)."
function answer_set_general_undefined(
    gd::PL_global_data{T}, atrie::trie{T}, nid::Int
)::Nothing where {T}
    destroy_delay_info(gd, atrie, nid, true)
    set_node_delayinfo(gd, atrie, nid, DL_UNDEFINED_INFO)
    return nothing
end

# PORT: pl-tabling.c delete_depending_answers
# (pl-tabling.c:1098 at the pin)
# DIVERGES: `wlset` is a vector (upstream a `TmpBuffer`); an entry of `wl.delays` names its trie (see the REPRESENTATION note).
"Make the conditional answers that depend on `wl` undefined; their worklists go on `wlset` (pl-tabling.c)."
function delete_depending_answers(
    gd::PL_global_data{T}, wl::tbl_worklist{T}, wlset::Vector{tbl_worklist{T}}
)::Nothing where {T}
    while !isempty(wl.delays)
        top = wl.delays[end]
        at = gd.tries[top.variant]
        di = node_delayinfo(gd, at, top.answer)
        if DL_IS_DELAY_LIST(di)
            at = gd.tries[di.variant]                           # value_trie(di->variant->value)
            dwl = at.worklist
            if dwl isa worklist && !dwl.depend_abolish
                dwl.depend_abolish = true
                push!(wlset, dwl)
            end
            answer_set_general_undefined(gd, at, top.answer)
        else
            pop!(wl.delays)
        end
    end
    empty!(wl.delays)
    return nothing
end

# PORT: pl-tabling.c destroy_depending_worklists
# (pl-tabling.c:1151 at the pin)
# Calls `delayed_destroy_table(atrie)::Bool` (:4495) and `destroy_answer_trie(ld, atrie)` (:4472): batch 3 holds a minimal port of both, TB5's.
"Destroy the worklists that have answers depending on `wl0` and its answers (pl-tabling.c)."
function destroy_depending_worklists(
    ld::PL_local_data{T}, wl0::tbl_worklist{T}
)::Nothing where {T}
    gd = _query_gd(ld)
    wlset = tbl_worklist{T}[]
    wl0.depend_abolish = true
    delete_depending_answers(gd, wl0, wlset)
    while !isempty(wlset)
        wl = pop!(wlset)
        delete_depending_answers(gd, wl, wlset)
        atrie = gd.tries[wl.table]
        delayed_destroy_table(atrie) || destroy_answer_trie(ld, atrie)  # (*)
    end
    return nothing
end

# PORT: pl-tabling.c destroy_delay_info_answer
# (pl-tabling.c:1169 at the pin)
"Make answer `nid` of `atrie` undefined if it has a delay list (pl-tabling.c); `nothing` to continue the walk."
function destroy_delay_info_answer(
    gd::PL_global_data{T}, atrie::trie{T}, nid::Int
)::Nothing where {T}
    if DL_IS_DELAY_LIST(node_delayinfo(gd, atrie, nid))
        answer_set_general_undefined(gd, atrie, nid)
    end
    return nothing
end

# PORT: pl-tabling.c destroy_delay_info_worklist
# (pl-tabling.c:1181 at the pin)
"Make every answer of `wl`'s table with a delay list undefined (pl-tabling.c)."
function destroy_delay_info_worklist(
    gd::PL_global_data{T}, wl::tbl_worklist{T}
)::Nothing where {T}
    atrie = gd.tries[wl.table]
    map_trie_node(atrie, 1, (tr, nid) -> destroy_delay_info_answer(gd, tr, nid))
    return nothing
end

# PORT: pl-tabling.c create_delay_set
# (pl-tabling.c:1187 at the pin)
"A new, empty delay set at the end of `di`'s sets; `nothing` when `di` is (pl-tabling.c)."
function create_delay_set(di::Union{Nothing, delay_info})::Union{Nothing, delay_set}
    di === nothing && return nothing
    ds = delay_set(length(di.delays), 0, UInt32(0))
    push!(di.delay_sets, ds)
    return ds
end

# PORT: pl-tabling.c add_to_delay_set
# (pl-tabling.c:1203 at the pin)
"Add the delay (`variant`, `answer`) to the set `ds` of `di`; the set's new size (pl-tabling.c)."
function add_to_delay_set(di::delay_info, ds::delay_set, variant::Int, answer::Int)::Int
    push!(di.delays, delay(variant, answer))
    variant != 0 && (ds.active += UInt32(1))
    ds.size += 1
    return ds.size
end

# PORT: pl-tabling.c add_to_wl_delays
# (pl-tabling.c:1227 at the pin)
# DIVERGES: the conditional answer is `(serial, nid)`; upstream asserts in the not-a-worklist branch.
"Register the conditional answer `nid` of the trie `serial` with the worklist of `at`, a table of its condition (pl-tabling.c)."
function add_to_wl_delays(
    at::trie{T}, serial::Int, nid::Int, wla::tbl_worklist{T}
)::Bool where {T}
    wl = at.worklist
    if wl isa worklist
        push!(wl.delays, delay(serial, nid))
    end                                                         # else: see '$tbl_table_complete_all'/3
    return true
end

# PORT: pl-tabling.c add_to_wl_pos_undefined
# (pl-tabling.c:1259 at the pin)
"Record the positive undefined answer `an` of `at` with `wl` (pl-tabling.c)."
function add_to_wl_pos_undefined(
    wl::tbl_worklist{T}, at::trie{T}, an::Int
)::Nothing where {T}
    push!(wl.pos_undefined, answer_ref(at.serial, an))
    return nothing
end

# PORT: pl-tabling.c equal_delay
# (pl-tabling.c:1270 at the pin)
"Whether the delays `a` and `b` are the same (pl-tabling.c)."
equal_delay(a::delay, b::delay)::Bool = a.variant == b.variant && a.answer == b.answer

# PORT: pl-tabling.c equal_delay_set
# (pl-tabling.c:1276 at the pin)
"Whether the delay sets `a` and `b` over `delays` hold the same delays (pl-tabling.c)."
function equal_delay_set(delays::Vector{delay}, a::delay_set, b::delay_set)::Bool
    if a.size == b.size
        ib = b.offset
        for ia in a.offset:(a.offset + a.size - 1)
            equal_delay(delays[ia + 1], delays[ib + 1]) || return false
            ib += 1
        end
        return true
    end
    return false
end

# PORT: pl-tabling.c simplify_delay_set
# (pl-tabling.c:1295 at the pin)
"Pop the new delay set `ds` of `di` if it duplicates an older one (pl-tabling.c); whether it did."
function simplify_delay_set(di::delay_info, ds::delay_set)::Bool
    for base in di.delay_sets
        base === ds && break
        if equal_delay_set(di.delays, base, ds)
            resize!(di.delays, ds.offset)                       # seekBuffer(&di->delays, ds->offset, delay)
            pop!(di.delay_sets)
            return true
        end
    end
    return false
end

# PORT: pl-tabling.c word_to_answer
# (pl-tabling.c:1313 at the pin)
# DIVERGES: the tagged integer is the answer's handle `trie_node_handle` = `serial << 32 | nid` (upstream: the node's address, the
# integer `trie_term/2` takes); the caller knows the trie, so the node id is the low 32 bits (gate 13 class M).
"The answer node id of the tagged integer `w`, the low half of its handle (pl-tabling.c)."
word_to_answer(w::word)::Int = Int(valInt(w)) & 0xffffffff

# ORIGINAL (TAB1 stack): `UDL_FALSE`, `UDL_TRUE` and `UDL_COMPLETE` (pl-tabling.c `udl_status`) are defined once, in the TB3 block above (a second definition of a `const` with a docstring is a docs-replacement warning).

# ORIGINAL: upstream's `undef:` label of update_delay_list_any (a deleted trie or 'undefined' in a delay list).
"Make answer `nid` of `atrie` generally undefined (update_delay_list_any's `undef:`); `UDL_TRUE`."
function _udl_undefined(gd::PL_global_data{T}, atrie::trie{T}, nid::Int)::Int where {T}
    destroy_delay_info(gd, atrie, nid, true)
    set_node_delayinfo(gd, atrie, nid, DL_UNDEFINED_INFO)
    return UDL_TRUE
end

# PORT: pl-tabling.c update_delay_list_any
# (pl-tabling.c:1342 at the pin)
# DIVERGES: see the REPRESENTATION note above (FLI walk, no retry); `answer` is a node id of `wl`'s table. The IDG branch
# (`wl->table->data.IDG->reevaluating`, :1365) is TB6's: `data.IDG` is `Nothing` until TB6 widens it.
"Store the delay list (`delays` + the global one) of the new answer `answer` of `wl`'s table (pl-tabling.c); a `UDL_*`."
function update_delay_list_any(
    ld::PL_local_data{T}, wl::tbl_worklist{T}, answer::Int, skel::term_t, delays::term_t
)::Int where {T}
    gd = _query_gd(ld)
    atrie = gd.tries[wl.table]
    gdl = PL_new_term_ref(ld)
    _PL_get_arg(ld, 1, ld.tabling.delay_list, gdl)              # gdlp = argTermP(*gdlp, 0)

    if PL_get_nil(ld, delays) && PL_get_nil(ld, gdl)
        di = node_delayinfo(gd, atrie, answer)
        if di !== nothing
            destroy_delay_info(gd, atrie, answer, true)
            set_node_delayinfo(gd, atrie, answer, nothing)
            wl.undefined -= 1
            simplify_answer(ld, wl, answer, true)
        end
        # Incremental tabling
        atrie.IDG !== nothing &&
            tbl_refuse(T, :update_delay_list_any, "IDG reevaluation", "TB6")
        wl.ground && return UDL_COMPLETE                        # early completion
        return UDL_TRUE
    else
        di = answer_delay_info(gd, wl, atrie, answer, true)
        ds = create_delay_set(di)

        rc, _ = PL_skip_list(ld, delays)
        rc == PL_LIST || (PL_type_error(ld, "delay_list", delays); return UDL_FALSE)
        rc, _ = PL_skip_list(ld, gdl)
        rc == PL_LIST ||
            (PL_type_error(ld, "delay_list", ld.tabling.delay_list); return UDL_FALSE)

        if ds !== nothing && di !== nothing
            tshare = term_t[]                                   # skel, then the shared non-ground answers
            l = PL_new_term_ref(ld)
            h = PL_new_term_ref(ld)
            p = PL_new_term_ref(ld)
            for pass in 0:1
                PL_put_term(ld, l, pass == 1 ? delays : gdl)
                while PL_get_list(ld, l, h, l)
                    an = 0
                    _, hw = trie_deref(ld, -(h + 1))
                    if isAtomW(hw)                              # Answer trie symbol
                        at = symbol_trie(gd, hw)
                        at === nothing && return _udl_undefined(gd, atrie, answer)  # deleted trie or 'undefined'
                    elseif PL_is_functor(ld, h, mk_sym(T, :+), 2)
                        _PL_get_arg(ld, 1, h, p)
                        _, aw = trie_deref(ld, -(p + 1))
                        at = symbol_trie(gd, aw)
                        at === nothing && return _udl_undefined(gd, atrie, answer)
                        _PL_get_arg(ld, 2, h, p)
                        _, pw = trie_deref(ld, -(p + 1))
                        if isTaggedIntW(pw)
                            an = word_to_answer(pw)
                        else
                            if ground_cells(ld, -(p + 1)) != 0  # ground() returns first var
                                isempty(tshare) && push!(tshare, PL_copy_term_ref(ld, skel))
                                push!(tshare, PL_copy_term_ref(ld, p))
                            end
                            if (at.flags & TRIE_ISMAP) != 0     # answer subsumption
                                r = PL_new_term_ref(ld)
                                _PL_get_arg(ld, 1, p, r)
                                rc, root = trie_lookup_abstract(
                                    ld, at, 0, -(r + 1), true, nothing, nothing
                                )
                                if rc == 1
                                    _PL_get_arg(ld, 2, p, r)
                                    rc, an = trie_lookup_abstract(
                                        ld, at, root, -(r + 1), true, nothing, nothing
                                    )
                                end
                            else
                                rc, an = trie_lookup_abstract(
                                    ld, at, 0, -(p + 1), true, nothing, nothing
                                )
                            end
                            if rc == 1
                                add_to_wl_pos_undefined(wl, at, an)
                            else
                                return if trie_trie_error(gd, ld, rc, at)
                                    UDL_TRUE
                                else
                                    UDL_FALSE
                                end
                            end
                        end
                    else
                        PL_type_error(ld, "delay_list", delays)
                        return UDL_FALSE
                    end
                    add_to_delay_set(di, ds, at.serial, an)
                end
            end

            if !isempty(tshare)
                n = length(tshare)
                a0 = PL_new_term_refs(ld, n)
                for i in 1:n
                    PL_put_term(ld, a0 + i - 1, tshare[i])
                end
                v = PL_new_term_ref(ld)
                fd = lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :v)), n)
                PL_cons_functor_v(ld, v, fd, a0) || return UDL_FALSE
                slot = Int(new_record_value!(atrie, PL_record(ld, v)) >> 2)
                add_to_delay_set(di, ds, 0, REC_DELAY(slot))
                di.has_share_records = UInt32(1)
            end

            if !isempty(tshare) || !simplify_delay_set(di, ds)
                for i in (ds.offset + 1):(ds.offset + ds.size)
                    d = di.delays[i]
                    if d.variant != 0
                        add_to_wl_delays(gd.tries[d.variant], atrie.serial, answer, wl) ||
                            return UDL_FALSE
                    end
                end
            end
            return UDL_TRUE
        end
        PL_resource_error(ld, "memory")                         # nomem:
        return UDL_FALSE
    end
end

# PORT: pl-tabling.c update_delay_list
# (pl-tabling.c:1544 at the pin)
# DIVERGES: the IDG test is `data.IDG !== nothing` (`Nothing` until TB6, which adds `->reevaluating`).
"update_delay_list_any for the common case of an unconditional answer without delay information inline (pl-tabling.c)."
function update_delay_list(
    ld::PL_local_data{T}, wl::tbl_worklist{T}, answer::Int, skel::term_t, delays::term_t
)::Int where {T}
    gd = _query_gd(ld)
    atrie = gd.tries[wl.table]
    gdl = PL_new_term_ref(ld)
    _PL_get_arg(ld, 1, ld.tabling.delay_list, gdl)
    if PL_get_nil(ld, delays) && PL_get_nil(ld, gdl) &&
        node_delayinfo(gd, atrie, answer) === nothing &&
        atrie.IDG === nothing
        return wl.ground ? UDL_COMPLETE : UDL_TRUE
    end
    return update_delay_list_any(ld, wl, answer, skel, delays)
end

# PORT: pl-tabling.c delay_sets
# (pl-tabling.c:1567 at the pin)
"The delay sets of `di` (pl-tabling.c; upstream: base and top pointers)."
delay_sets(di::delay_info)::Vector{delay_set} = di.delay_sets

# PORT: pl-tabling.c get_delay_set
# (pl-tabling.c:1573 at the pin)
"The delays of the set `set` of `di` (pl-tabling.c; upstream: base and top pointers)."
get_delay_set(di::delay_info, set::delay_set) =
    view(di.delays, (set.offset + 1):(set.offset + set.size))

# PORT: pl-tabling.c init_delay_list
# (pl-tabling.c:1580 at the pin)
"A new term reference holding `-([])`, the empty global delay list (pl-tabling.c)."
function init_delay_list(ld::PL_local_data{T})::term_t where {T}
    t = PL_new_term_ref(ld)
    a = PL_new_term_ref(ld)
    PL_put_nil(ld, a)
    PL_cons_functor_v(
        ld, t, lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :-)), 1), a
    )
    return t
end

# PORT: pl-tabling.c PL_get_delay_list
# (pl-tabling.c:1593 at the pin)
# DIVERGES: for `t == 0` the argument goes to a new term reference (upstream reads the word).
"Whether the global delay list is not empty; it goes to `t` unless `t` is 0 (pl-tabling.c)."
function PL_get_delay_list(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    dl = ld.tabling.delay_list
    a = t != 0 ? t : PL_new_term_ref(ld)
    _PL_get_arg(ld, 1, dl, a)
    return !PL_get_nil(ld, a)
end

# PORT: pl-tabling.c tbl_delay_list as pl_tbl_delay_list1_va
# (PRED_IMPL("$tbl_delay_list", 1, tbl_delay_list, 0))
"`'\$tbl_delay_list'(-List)`: the global delay list (pl-tabling.c)."
function pl_tbl_delay_list1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    dl = ld.tabling.delay_list
    a = PL_new_term_ref(ld)
    return (_PL_get_arg(ld, 1, dl, a) && PL_unify(ld, A1, a)) ? FTRUE : FFALSE
end

# PORT: pl-tabling.c tbl_set_delay_list as pl_tbl_set_delay_list1_va
# (PRED_IMPL("$tbl_set_delay_list", 1, tbl_set_delay_list, 0))
# DIVERGES: the argument cell is `valPtr(w) + 1` of the dereferenced `-(List)` (upstream `argTermP(*p, 0)`).
"`'\$tbl_set_delay_list'(+List)`: set the global delay list, backtrackable (pl-tabling.c)."
function pl_tbl_set_delay_list1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    dl = ld.tabling.delay_list
    ensureGlobalSpace(ld, 0) || return FFALSE
    k, w, _ = _deref_loc(ld, -(dl + 1))                        # p = valTermRef(dl)
    if k == DU_WORD && _is_gcompound(w)                         # if ( isTerm(*p) )
        p = valPtr(w) + 1                                       # p = argTermP(*p, 0)
        TrailAssignment!(ld, p)
        unify_vp(ld, p, -(A1 + 1))
    end
    return FTRUE
end

# PORT: pl-tabling.c push_delay_list
# (pl-tabling.c:1644 at the pin)
# DIVERGES: the new list cell `[H|Old]` is built with the FLI from the term `h` (upstream fills the cell `p` the caller
# allocated); the trailed assignment of the delay list's argument is upstream's.
"Push the delay element `h` on the global delay list, backtrackable (pl-tabling.c)."
function push_delay_list(ld::PL_local_data{T}, h::term_t)::Nothing where {T}
    dl = ld.tabling.delay_list
    c = PL_new_term_refs(ld, 2)
    PL_put_term(ld, c, h)
    _PL_get_arg(ld, 1, dl, c + 1)                               # p[2] = *dl
    l = PL_new_term_ref(ld)
    PL_cons_functor_v(ld, l, ld.functor_dot2, c)
    _, w, _ = _deref_loc(ld, -(dl + 1))
    p = valPtr(w) + 1                                           # dl = argTermP(*dl, 0)
    TrailAssignment!(ld, p)
    unify_vp(ld, p, -(l + 1))                                   # *dl = consCompound(p)
    return nothing
end

# PORT: pl-tabling.c delay_to_data
# (pl-tabling.c:1660 at the pin)
# DIVERGES: the data goes to the term reference `out`; a ground answer is its handle `trie_node_handle` (upstream: its address,
# which `trie_term/2` reads in `delay_goals`, boot/tabling.pl:1060; gate 13 class M: the node id alone named no trie); `at` is the
# answer's trie (for `is_ground_trie_node`; `nothing` with `answer` 0, T_DELAY's NULL node).
"The delay data of `answer` of `at`: 0 for none, the node handle if ground, else the `wrapper` (pl-tabling.c)."
function delay_to_data(
    ld::PL_local_data{T}, at::Union{Nothing, trie{T}}, answer::Int, wrapper::term_t,
    out::term_t
)::Nothing where {T}
    # `at` is `nothing` only with `answer` 0 (T_DELAY's NULL node)
    if answer == 0 || at === nothing
        PL_put_integer(ld, out, 0)
    elseif is_ground_trie_node(at, answer)
        PL_put_integer(ld, out, trie_node_handle(at, answer))
    else
        PL_put_term(ld, out, wrapper)                           # linkValI(wrapper)
    end
    return nothing
end

# PORT: pl-tabling.c tbl_push_delay
# (pl-tabling.c:1696 at the pin)
# DIVERGES: `atrie` is the answer trie's symbol word with the trie `at` beside it; `wrapper` a term reference; the term
# `atrie+Data` is built with the FLI (upstream: six cells from allocGlobalNoShift).
"Push `atrie+Data` (the positive delay of `answer`) on the global delay list (pl-tabling.c)."
function tbl_push_delay(
    ld::PL_local_data{T}, atrie::word, at::Union{Nothing, trie{T}}, wrapper::term_t,
    answer::Int
)::Nothing where {T}
    a = PL_new_term_refs(ld, 2)
    ld.slots[a + 1] = atrie                                     # p[4] = atrie (PL_put_atom's setHandle)
    delay_to_data(ld, at, answer, wrapper, a + 1)               # p[5] = p5
    d = PL_new_term_ref(ld)
    PL_cons_functor_v(
        ld, d, lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :+)), 2), a
    )
    push_delay_list(ld, d)
    return nothing
end

# PORT: pl-vmi.c T_DELAY as t_delay!
# (pl-vmi.c:6225-6249 at the pin: VMI(T_DELAY, 0, 1, (CA1_TRIE_NODE)); the note (*) is :6211-6223.)
# DIVERGES: the body after `ENSURE_STACK_SPACE(16, 12)` and `UnwindTrieArgP()` is this function, called by the run loop's
# `T_DELAY` arm (TR4 declares `T_DELAY`, code 173, and owns `UnwindTrieArgP` and the frame's trie state cells,
# `_trie_state_cell`); the operand `h` is TR4's `trie_node_handle` = `answer_ref(serial, nid)` (0: upstream's NULL node);
# `get_trie_from_node(answer)` is the trie of the handle's serial; `argTermP(*TrieTermP, 0)` is a term reference to argument 1
# of the compound in the TrieTermP cell.
# STACK EDIT (TR4, recorded in evidence/TB4/handoff2.md): `:T_DELAY` joins the run loop's dispatch tuple and the run loop
# gains, beside TR4's T_* arms: `@label T_DELAY` / UnwindTrieArgP (TR4's form) / `t_delay!(ld, FR, Int(PCc[PC]))` /
# `PC += 1` / the next instruction (the FLI allocates as it goes: no ENSURE_STACK_SPACE).
"Push the delay of the answer `h` of a compiled trie's clause on the global delay list; nothing if it lost its delay info (pl-vmi.c `T_DELAY`)."
function t_delay!(ld::PL_local_data{T}, fr::Int, h::Int)::Nothing where {T}
    gd = _query_gd(ld)
    if h != 0
        at = gd.tries[answer_ref_trie(h)]::trie{T}
        nid = answer_ref_node(h)
        (at.nodes[nid].flags & TN_DELAYINFO) == 0 && return nothing     # (*)
        atrie = trie_symbol(gd, at)
    else                                                                # generally undefined; see
        at = nothing                                                    # set_trie_clause_general_undefined()
        nid = 0
        atrie = ld.atom_nil_w
    end
    tt = PL_new_term_ref(ld)
    ld.slots[tt + 1] = makeRefG(_trie_state_cell(ld, fr, 0))           # *TrieTermP
    wrapper = PL_new_term_ref(ld)
    _PL_get_arg(ld, 1, tt, wrapper)                                     # argTermP(*TrieTermP, 0)
    tbl_push_delay(ld, atrie, at, wrapper, nid)
    return nothing
end

# PORT: pl-tabling.c tbl_add_global_delays as pl_tbl_add_global_delays2_va
# (PRED_IMPL("$tbl_add_global_delays", 2, tbl_add_global_delays, 0))
# DIVERGES: the copy of the global list ending in `Delays0` is built with the FLI from its last element backwards (upstream
# lays out the cells forwards).
"`'\$tbl_add_global_delays'(+Delays0, -Delays)`: `Delays` is the global delay list appended with `Delays0` (pl-tabling.c)."
function pl_tbl_add_global_delays2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    A2 = PL__t0 + 1
    dl = PL_new_term_ref(ld)
    _PL_get_arg(ld, 1, ld.tabling.delay_list, dl)
    if PL_get_nil(ld, dl)
        return PL_unify(ld, A1, A2) ? FTRUE : FFALSE
    elseif PL_get_nil(ld, A1)
        return PL_unify(ld, A2, dl) ? FTRUE : FFALSE
    else
        heads = term_t[]
        l = PL_copy_term_ref(ld, dl)
        while true
            h = PL_new_term_ref(ld)
            PL_get_list(ld, l, h, l) || break
            push!(heads, h)
        end
        tail = PL_copy_term_ref(ld, A1)                         # *p = linkValI(valTermRef(A1))
        for i in length(heads):-1:1
            c = PL_new_term_refs(ld, 2)
            PL_put_term(ld, c, heads[i])
            PL_put_term(ld, c + 1, tail)
            PL_cons_functor_v(ld, tail, ld.functor_dot2, c)
        end
        return PL_unify(ld, A2, tail) ? FTRUE : FFALSE
    end
end

#                *******************************
#                *        SIMPLIFICATION        *
#                *******************************

# PORT: pl-tabling.c propagate
# (pl-tabling.c:1771 at the pin)
# DIVERGES: `answer` is an `answer_ref` (0: NULL) of the answer to propagate.
"One propagation step of the simplification agenda (pl-tabling.c `struct propagate`)."
struct propagate{T}
    worklist::tbl_worklist{T}
    answer::Int
    result::Bool
end

# PORT: pl-tabling.c spf_agenda
# (pl-tabling.c:1777 at the pin)
"The simplification agenda (pl-tabling.c `spf_agenda`): the answers changed and the steps to do."
mutable struct spf_agenda{T}
    done::Int
    buffer::Vector{propagate{T}}
end

# PORT: pl-tabling.c init_spf_agenda
# (pl-tabling.c:1783 at the pin)
"A new, empty agenda (pl-tabling.c)."
init_spf_agenda(::Type{T}) where {T} = spf_agenda{T}(0, propagate{T}[])

# PORT: pl-tabling.c exit_spf_agenda
# (pl-tabling.c:1789 at the pin)
"Discard the agenda's steps (pl-tabling.c)."
function exit_spf_agenda(a::spf_agenda{T})::Nothing where {T}
    empty!(a.buffer)
    return nothing
end

# PORT: pl-tabling.c push_propagate
# (pl-tabling.c:1794 at the pin)
"Push the step (`wl`, `answer`, `result`) on the agenda (pl-tabling.c)."
function push_propagate(
    a::spf_agenda{T}, wl::tbl_worklist{T}, answer::Int, result::Bool
)::Bool where {T}
    push!(a.buffer, propagate{T}(wl, answer, result))
    return true
end

# PORT: pl-tabling.c pop_propagate
# (pl-tabling.c:1805 at the pin)
"The last step of the agenda, removed; `nothing` when empty (pl-tabling.c)."
function pop_propagate(a::spf_agenda{T})::Union{Nothing, propagate{T}} where {T}
    isempty(a.buffer) && return nothing
    return pop!(a.buffer)
end

# PORT: pl-tabling.c make_answer_unconditional
# (pl-tabling.c:1820 at the pin)
# DIVERGES: the answer is `nid` of `atrie` (its delay info names the same trie).
"Make answer `nid` of `atrie` unconditional and schedule its propagation (pl-tabling.c)."
function make_answer_unconditional(
    gd::PL_global_data{T}, agenda::spf_agenda{T}, atrie::trie{T}, nid::Int
)::Bool where {T}
    di = node_delayinfo(gd, atrie, nid)
    if DL_IS_DELAY_LIST(di)
        at = gd.tries[di.variant]                               # value_trie(di->variant->value)
        wl = at.worklist::tbl_worklist{T}
        destroy_delay_info(gd, at, nid, true)
        agenda.done += 1
        wl.undefined -= 1
        isempty(wl.delays) || push_propagate(agenda, wl, answer_ref(at.serial, nid), true)
    end                                                         # else: upstream asserts
    return true
end

# PORT: pl-tabling.c remove_conditional_answer
# (pl-tabling.c:1846 at the pin)
"Remove the conditional answer `nid` of `atrie` and schedule its propagation (pl-tabling.c)."
function remove_conditional_answer(
    gd::PL_global_data{T}, agenda::spf_agenda{T}, atrie::trie{T}, nid::Int
)::Bool where {T}
    di = node_delayinfo(gd, atrie, nid)
    if DL_IS_DELAY_LIST(di)
        at = gd.tries[di.variant]
        wl = at.worklist::tbl_worklist{T}
        destroy_delay_info(gd, at, nid, true)
        trie_delete(gd, at, nid, true)                              # cannot prune as may be
        agenda.done += 1                                        # in worklist delay lists
        wl.undefined -= 1
        isempty(wl.delays) || push_propagate(agenda, wl, answer_ref(at.serial, nid), false)
    end
    return true
end

# PORT: pl-tabling.c answer_delay_sets
# (pl-tabling.c:1873 at the pin)
"The delay sets of `di` (pl-tabling.c; upstream: base and top pointers)."
answer_delay_sets(di::delay_info)::Vector{delay_set} = di.delay_sets

# PORT: pl-tabling.c propagate_to_answer
# (pl-tabling.c:1900 at the pin)
# DIVERGES: `panswer` is an `answer_ref` (0: NULL), compared with a delay as `answer_ref(d.variant, d.answer)`; the
# conditional answer is `nid` of `atrie`; the memmove of the delay sets is `deleteat!`.
"Propagate (`wl`, `panswer`, `result`) to the conditional answer `nid` of `atrie` (pl-tabling.c); whether a delay matched."
function propagate_to_answer(
    gd::PL_global_data{T}, agenda::spf_agenda{T}, wl::tbl_worklist{T}, panswer::Int,
    result::Bool,
    atrie::trie{T}, nid::Int
)::Bool where {T}
    variant = wl.table
    found = false
    di = node_delayinfo(gd, atrie, nid)                         # answer_delay_info(NULL, answer, false)
    if di !== nothing
        db = di.delays
        k = 1
        while k <= length(di.delay_sets)
            ds = di.delay_sets[k]
            removed = false
            for o in ds.offset:(ds.offset + ds.size - 1)
                d = db[o + 1]
                if d.variant == variant
                    if d.answer == 0 || answer_ref(d.variant, d.answer) == panswer
                        res = false
                        if d.answer == 0
                            if result == false && (wl.has_answers || wl.undefined != 0)
                                continue
                            end
                            res = !result
                        else
                            res = result
                        end
                        found = true
                        c = wl.component
                        c === nothing || (c.simplifications += 1)  # (*)
                        if res                                  # remove member from conjunction
                            db[o + 1] = delay(
                                DV_DELETED,
                                d.answer == 0 ? 0 : answer_ref(d.variant, d.answer)
                            )   # the answer's trie goes with `variant`: `put_delay_set` reads it back
                            ds.active -= UInt32(1)
                            if ds.active == 0
                                make_answer_unconditional(gd, agenda, atrie, nid)
                                return found
                            end
                        else                                    # remove the conjunction
                            deleteat!(di.delay_sets, k)
                            removed = true                      # compensate for(;;ds++)
                            break
                        end
                    end
                end
            end
            if isempty(di.delay_sets)
                remove_conditional_answer(gd, agenda, atrie, nid)
                return found
            end
            removed || (k += 1)
        end
    end
    return found
end

# PORT: pl-tabling.c answer_delays_on
# (pl-tabling.c:1986 at the pin)
"Whether answer `nid` of `atrie_of_answer` has a live delay element on the answer trie with serial `serial` (pl-tabling.c)."
function answer_delays_on(
    gd::PL_global_data{T}, atrie_of_answer::trie{T}, nid::Int, serial::Int
)::Bool where {T}
    di = node_delayinfo(gd, atrie_of_answer, nid)
    if DL_IS_DELAY_LIST(di)
        for ds in answer_delay_sets(di)
            for o in ds.offset:(ds.offset + ds.size - 1)
                di.delays[o + 1].variant == serial && return true
            end
        end
    end
    return false
end

# PORT: pl-tabling.c propagate_result
# (pl-tabling.c:2023 at the pin)
"Propagate (`wl`, `panswer`, `result`) to the answers that delay on `wl`'s table (pl-tabling.c)."
function propagate_result(
    gd::PL_global_data{T}, agenda::spf_agenda{T}, wl::tbl_worklist{T}, panswer::Int,
    result::Bool
)::Bool where {T}
    i = 1
    while i <= length(wl.delays)
        e = wl.delays[i]
        at = gd.tries[e.variant]
        propagate_to_answer(gd, agenda, wl, panswer, result, at, e.answer)
        if i <= length(wl.delays) && wl.delays[i] == e
            if answer_delays_on(gd, at, e.answer, wl.table)     # (*)
                i += 1
            else
                delete_answer(wl.delays, e.variant, e.answer)
            end
        end
    end
    return true
end

# ORIGINAL: upstream's `while( (p=pop_propagate(&agenda)) ) propagate_result(...)` loop, used five times.
"Run the agenda's steps until it is empty."
function _run_agenda(gd::PL_global_data{T}, agenda::spf_agenda{T})::Nothing where {T}
    while true
        p = pop_propagate(agenda)
        p === nothing && break
        propagate_result(gd, agenda, p.worklist, p.answer, p.result)
    end
    return nothing
end

# PORT: pl-tabling.c simplify_answer
# (pl-tabling.c:2053 at the pin)
# DIVERGES: `answer` is a node id of `wl`'s table (its `answer_ref` is propagated).
"Propagate the truth `truth` of answer `answer` of `wl`'s table (pl-tabling.c)."
function simplify_answer(
    ld::PL_local_data{T}, wl::tbl_worklist{T}, answer::Int, truth::Bool
)::Bool where {T}
    gd = _query_gd(ld)
    agenda = init_spf_agenda(T)
    push_propagate(agenda, wl, answer_ref(wl.table, answer), truth)
    _run_agenda(gd, agenda)
    exit_spf_agenda(agenda)
    return true
end

# PORT: pl-tabling.c live_answer_node
# (pl-tabling.c:2076 at the pin)
"`nid` if it is a live answer (a value, not `TN_IDG_DELETED`), else `nothing` (pl-tabling.c)."
function live_answer_node(tr::trie{T}, nid::Int)::Union{Nothing, Int} where {T}
    n = tr.nodes[nid]
    (n.value != 0 && (n.flags & TN_IDG_DELETED) == 0) && return nid
    return nothing
end

# PORT: pl-tabling.c table_has_no_answers
# (pl-tabling.c:2086 at the pin)
# DIVERGES: the re-evaluation branch (`data.IDG->reevaluating`) is TB6's; `data.IDG` is `Nothing` until TB6.
"Whether the answer trie has no answers (pl-tabling.c)."
function table_has_no_answers(atrie::trie{T})::Bool where {T}
    atrie.value_count == 0 && return true
    if atrie.IDG !== nothing
        return map_trie_node(atrie, 1, live_answer_node) === nothing
    end
    return false
end

# PORT: pl-tabling.c simplify_component
# (pl-tabling.c:2099 at the pin)
# DIVERGES: O_AC_EAGER is defined at the pin (:72), so the `#ifndef O_AC_EAGER` parts (`simplified0`, :2106 and :2181) are
# left out as upstream compiles them; `pos_undefined` holds `answer_ref`s.
# NOTE: `clean_worklist(ld, wl)` (pl-tabling.c :3932-3953, TB2) takes the engine, as the freeing of its clusters needs it (gate 13 class L).
"Simplify the conditional answers of the component `scc`; answer completion if undefined answers remain (pl-tabling.c)."
function simplify_component(ld::PL_local_data{T}, scc::tbl_component{T})::Bool where {T}
    gd = _query_gd(ld)
    wls = scc.created_worklists::worklist_set{tbl_worklist{T}}
    agenda = init_spf_agenda(T)
    undefined = 0
    pass = 0
    while true
        count = 0
        undefined = 0
        for wl in wls.members
            pass == 0 && clean_worklist(ld, wl)
            if wl.negative && wl.neg_delayed && !isempty(wl.delays) &&
                table_has_no_answers(gd.tries[wl.table])
                count += 1
                push_propagate(agenda, wl, 0, false)
                _run_agenda(gd, agenda)
            end
            if !isempty(wl.pos_undefined)
                on = 0
                for bn in 1:length(wl.pos_undefined)
                    r = wl.pos_undefined[bn]
                    at = gd.tries[answer_ref_trie(r)]
                    an = answer_ref_node(r)
                    if !answer_is_conditional(gd, at, an)
                        count += 1
                        push_propagate(agenda, wl, r, at.nodes[an].value != 0)
                        _run_agenda(gd, agenda)
                    else
                        on += 1
                        wl.pos_undefined[on] = r
                    end
                end
                resize!(wl.pos_undefined, on)
            end
            wl.undefined != 0 && (undefined += 1)
        end
        (count == 0 || undefined == 0) && break
        pass += 1
    end
    exit_spf_agenda(agenda)
    # DSW: there cannot be any "uncovering" of a positive loop if there was no simplification
    if undefined != 0 && scc.simplifications != 0
        return answer_completion(ld, scc)
    else
        return true
    end
end

#                *******************************
#                *      ANSWER COMPLETION       *
#                *******************************

# PORT: pl-tabling.c call_answer_completion
# (pl-tabling.c:2241 at the pin)
# DIVERGES: `'$tabling':answer_completion/2` is looked up on each call (upstream caches it in
# `GD->procedures.answer_completion2`); `saved` is a `tbl_status`. ASSUMES (TB1): `unify_skeleton(ld, atrie, wrapper, skel)`.
"Call `'\$tabling':answer_completion(ATrie, Skeleton)` with the tabling state of a fresh evaluation (pl-tabling.c)."
function call_answer_completion(ld::PL_local_data{T}, atrie::trie{T})::Bool where {T}
    gd = _query_gd(ld)
    fid = PL_open_foreign_frame(ld)
    fid == 0 && return false                                    # stack overflow
    av = PL_new_term_refs(ld, 2)
    scc_old = ld.tabling.component
    hsc = ld.tabling.has_scheduling_component
    saved = tbl_status{T}(scc_old, ld.tabling.saved_status, false, false, false)  # for '$tbl_sdg'/3
    pred = lookupProcedure(
        mk_sym(T, :answer_completion), 2, lookupModule(gd, mk_sym(T, Symbol("\$tabling")))
    )
    ld.tabling.saved_status = saved
    ld.tabling.component = nothing
    ld.tabling.has_scheduling_component = false
    ld.tabling.in_answer_completion = true
    ld.slots[av + 1] = trie_symbol(gd, atrie)                   # PL_put_atom(av+0, trie_symbol(atrie))
    rc =
        unify_skeleton(ld, atrie, 0, av + 1) &&
        PL_call_predicate(gd, ld, nothing, PL_Q_PASS_EXCEPTION, pred, av)
    ld.tabling.in_answer_completion = false
    ld.tabling.has_scheduling_component = hsc
    ld.tabling.component = scc_old
    ld.tabling.saved_status = saved.prev
    PL_close_foreign_frame(ld, fid)
    return rc
end

# PORT: pl-tabling.c has_positive_dl
# (pl-tabling.c:2290 at the pin)
"Whether answer `nid` of `atrie` has a value and a live positive delay element (pl-tabling.c)."
function has_positive_dl(gd::PL_global_data{T}, atrie::trie{T}, nid::Int)::Bool where {T}
    atrie.nodes[nid].value == 0 && return false
    di = node_delayinfo(gd, atrie, nid)
    if DL_IS_DELAY_LIST(di)
        for ds in answer_delay_sets(di)
            for o in ds.offset:(ds.offset + ds.size - 1)
                d = di.delays[o + 1]
                if d.variant != 0 && d.variant != DV_DELETED
                    d.answer != 0 && return true
                end
            end
        end
    end
    return false
end

# PORT: pl-tabling.c is_ac_candidate_wl
# (pl-tabling.c:2316 at the pin)
"Whether `wl` is a candidate for answer completion: undefined answers, a positive delay among its dependents (pl-tabling.c)."
function is_ac_candidate_wl(gd::PL_global_data{T}, wl::tbl_worklist{T})::Bool where {T}
    if wl.undefined != 0 && !wl.answer_completed && !isempty(wl.delays)
        for e in wl.delays
            has_positive_dl(gd, gd.tries[e.variant], e.answer) && return true
        end
    end
    return false
end

# PORT: pl-tabling.c answer_completion
# (pl-tabling.c:2334 at the pin)
# DIVERGES: O_AC_EAGER is defined at the pin (:72): the eager branch only; the O_DEBUG `TABLING_NO_AC` test is left out.
"Answer completion of the component `scc` (pl-tabling.c): call it for each candidate worklist; not recursive."
function answer_completion(ld::PL_local_data{T}, scc::tbl_component{T})::Bool where {T}
    ld.tabling.in_answer_completion && return true              # not recursive!
    gd = _query_gd(ld)
    wls = scc.created_worklists::worklist_set{tbl_worklist{T}}
    for wl in wls.members
        if is_ac_candidate_wl(gd, wl)
            call_answer_completion(ld, gd.tries[wl.table]) || return false
        end
    end
    return true
end

# PORT: pl-tabling.c tbl_force_truth_value as pl_tbl_force_truth_value3_va
# (PRED_IMPL("$tbl_force_truth_value", 3, tbl_force_truth_value, 0))
# DIVERGES: the AnswerNode "pointer" is the integer `answer_ref(serial, nid)` (upstream: the node's address).
"`'\$tbl_force_truth_value'(+AnswerNode, +Value, -Count)`: force the answer's truth; Count answers changed (pl-tabling.c)."
function pl_tbl_force_truth_value3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    A2 = PL__t0 + 1
    A3 = PL__t0 + 2
    gd = _query_gd(ld)
    rc = false
    ptr = PL_get_pointer_ex(ld, A1)                             # PL_get_pointer_ex(A1, &ptr): type_error(address, A1) (pl-error.c:1335)
    truth = ptr === nothing ? nothing : PL_get_stdbool_ex(ld, A2)
    if ptr !== nothing && truth !== nothing
        atrie = gd.tries[answer_ref_trie(ptr)]
        answer = answer_ref_node(ptr)
        di = node_delayinfo(gd, atrie, answer)
        agenda = init_spf_agenda(T)
        if DL_IS_DELAY_LIST(di)
            at = gd.tries[di.variant]
            wl = at.worklist
            if wl isa worklist
                rc = if truth
                    make_answer_unconditional(gd, agenda, atrie, answer)
                else
                    remove_conditional_answer(gd, agenda, atrie, answer)
                end
            else
                rc = PL_error(
                    ld, "", 0, "", ERR_PERMISSION, mk_sym(T, :force_truth_value),
                    mk_sym(T, :answer), A1
                )
            end
        else                                                    # answer is not conditional
            truth || trie_delete(gd, atrie, answer, false)          # TBD: propagate?
            rc = true
        end
        while rc
            p = pop_propagate(agenda)
            p === nothing && break
            rc = propagate_result(gd, agenda, p.worklist, p.answer, p.result)
        end
        rc = rc && PL_unify_integer(ld, A3, agenda.done)
        exit_spf_agenda(agenda)
    end
    return rc ? FTRUE : FFALSE
end

# PORT: pl-tabling.c tbl_set_answer_completed as pl_tbl_set_answer_completed1_va
# (PRED_IMPL("$tbl_set_answer_completed", 1, tbl_set_answer_completed, 0))
"`'\$tbl_set_answer_completed'(+ATrie)`: mark the table's worklist answer completed (pl-tabling.c)."
function pl_tbl_set_answer_completed1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    tr = get_trie(_query_gd(ld), ld, A1)
    if tr !== nothing
        wl = tr.worklist
        if wl isa worklist
            wl.answer_completed = true
            return FTRUE
        end
        (tr.flags & TRIE_COMPLETE) != 0 && return FTRUE
        return if PL_error(
            ld, "", 0, "", ERR_PERMISSION, mk_sym(T, :set_answer_complete),
            mk_sym(T, :trie), A1
        )
            FTRUE
        else
            FFALSE
        end
    end
    return FFALSE
end

# PORT: pl-tabling.c tbl_is_answer_completed as pl_tbl_is_answer_completed1_va
# (PRED_IMPL("$tbl_is_answer_completed", 1, tbl_is_answer_completed, 0))
"`'\$tbl_is_answer_completed'(+ATrie)`: the table's worklist is answer completed, or the table is complete (pl-tabling.c)."
function pl_tbl_is_answer_completed1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    tr = get_trie(_query_gd(ld), ld, A1)
    if tr !== nothing
        wl = tr.worklist
        wl isa worklist && return wl.answer_completed ? FTRUE : FFALSE
        return (tr.flags & TRIE_COMPLETE) != 0 ? FTRUE : FFALSE
    end
    return FFALSE
end

#                *******************************
#                *   TB4b: WORKLIST NEGATION, UPDATE_DL  *
#                *******************************

# PORT: pl-tabling.c tbl_wkl_negative as pl_tbl_wkl_negative1_va
# (pl-tabling.c:5374-5380 at the pin: PRED_IMPL("$tbl_wkl_negative", 1, tbl_wkl_negative, 0))
# Owner TB4 (dispatcher decision); the same text as wip/tb2's, which also writes it: the stack keeps one. `get_worklist` and
# `worklist_negative` (pl-tabling.c :4409, :4023) are TB2's.
"`'\$tbl_wkl_negative'(+Worklist)`: true if the worklist is a suspended negation (pl-tabling.c)."
function pl_tbl_wkl_negative1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    wl = get_worklist(ld, A1)

    return (wl !== nothing && worklist_negative(ld, wl)) ? FTRUE : FFALSE
end

# PORT: pl-tabling.c tbl_wkl_is_false as pl_tbl_wkl_is_false1_va
# (pl-tabling.c:5392-5405 at the pin: PRED_IMPL("$tbl_wkl_is_false", 1, tbl_wkl_is_false, 0))
# Owner TB4 (dispatcher decision); the same text as wip/tb2's: the stack keeps one.
"`'\$tbl_wkl_is_false'(+Worklist)`: the negative node's negation was delayed and it has no unconditional answer (pl-tabling.c)."
function pl_tbl_wkl_is_false1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    wl = get_worklist(ld, A1)
    if wl !== nothing
        @assert wl.negative

        return (wl.neg_delayed && !wl.has_answers) ? FTRUE : FFALSE
    end

    return FFALSE
end

# ORIGINAL (TAB1 TB4): the `data_kind` of TR2's `trie_gen` / `trie_gen_raw` that selects `answer_update_delay_list` (upstream
# passes the function pointer `answer_update_delay_list` and its `update_dl_ctx` as `unify_data`, `ctx`). TB3's
# `TRIE_GEN_DELAY_INFO` is 2; 3 is left for `unify_delay_info_dl` (`$tbl_answer_dl`).
# STACK EDIT (TR2, done): `trie_gen_unify_data` (src/pl-trie.jl) has the arm
# `data_kind == TRIE_GEN_UPDATE_DL ? answer_update_delay_list(ld, Data, trs, nid)` beside TB3's `TRIE_GEN_DELAY_INFO` arm.
"`trie_gen` data kind: push the answer's delay on the global delay list if it is conditional (pl-tabling.c `answer_update_delay_list`)."
const TRIE_GEN_UPDATE_DL = 4

# PORT: pl-tabling.c answer_update_delay_list
# (pl-tabling.c:7229-7246 at the pin.)
# DIVERGES: the answer is its trie `tr` and node id (upstream: the `trie_node *`); the answer trie's symbol is
# `trie_symbol(gd, tr)` of the trie `trie_gen` enumerates, which is the atom of `ctx->atrie` (A1 of both callers: `trie_gen`
# reads its trie from A1), so the context `update_dl_ctx` is not kept; the `ensureStackSpace(10, 2)` is dropped
# (tbl_push_delay builds with the FLI).
"If answer `nid` of `tr` is conditional, push its delay `ATrie+Data` on the global delay list; true (pl-tabling.c)."
function answer_update_delay_list(
    ld::PL_local_data{T}, wrapper::term_t, tr::trie{T}, nid::Int
)::Bool where {T}
    gd = _query_gd(ld)
    if answer_is_conditional(gd, tr, nid)
        tbl_push_delay(ld, trie_symbol(gd, tr), tr, wrapper, nid)
    end

    return true
end

# PORT: pl-tabling.c tbl_answer_update_dl as pl_tbl_answer_update_dl2_va
# (PRED_IMPL("$tbl_answer_update_dl", 2, tbl_answer_update_dl, PL_FA_NONDETERMINISTIC), pl-tabling.c:7248-7256 at the pin.)
"`'\$tbl_answer_update_dl'(+ATrie, -Skeleton)`: the answers of `ATrie`; a conditional one also extends the global delay list (pl-tabling.c)."
function pl_tbl_answer_update_dl2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    A2 = PL__t0 + 1

    return trie_gen(_query_gd(ld), ld, A1, 0, A2, 0, A2, TRIE_GEN_UPDATE_DL, PL__ctx)
end

# PORT: pl-tabling.c tbl_answer_update_dl as pl_tbl_answer_update_dl3_va
# (PRED_IMPL("$tbl_answer_update_dl", 3, tbl_answer_update_dl, PL_FA_NONDETERMINISTIC), pl-tabling.c:7262-7290 at the pin.)
# DIVERGES: as TB3's pl_tbl_answer_c4_va: a redo or a cut goes to TR2's `trie_gen_raw` with no trie (its state holds the trie
# and the root: upstream looks the root up again on a redo and `trie_gen_raw` then ignores it; on a cut
# `clear_trie_gen_state` is `trie_gen_raw`'s `FRG_CUTTED`).
"`'\$tbl_answer_update_dl'(+Trie, +Skeleton, -ModeArgs)`: the moded answers below `Skeleton`; a conditional one also extends the global delay list (pl-tabling.c)."
function pl_tbl_answer_update_dl3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    A2 = PL__t0 + 1
    A3 = PL__t0 + 2

    if PL_foreign_control(PL__ctx) != FRG_FIRST_CALL   # FRG_CUTTED: clear_trie_gen_state(CTX_PTR); FRG_REDO
        return trie_gen_raw(ld, nothing, 0, A3, 0, A3, TRIE_GEN_UPDATE_DL, PL__ctx)
    end

    tr = get_trie_nodes(_query_gd(ld), ld, A1)
    if tr !== nothing
        rc, root = trie_lookup(ld, tr, 0, -(A2 + 1), false, nothing)
        if rc == 1
            return trie_gen_raw(ld, tr, root, A3, 0, A3, TRIE_GEN_UPDATE_DL, PL__ctx)
        else
            return trie_error(ld, rc, A1) ? FTRUE : FFALSE
        end
    end

    return FFALSE
end

# PORT: pl-tabling.c BeginPredDefs as PL_predicates_from_tabling
# (pl-tabling.c:12747-12789 at the pin for the entries below)
# DIVERGES: the ported entries, in upstream's order (upstream's table has the other `$tbl_*` predicates; `$tbl_trienode`
# and `$tbl_is_trienode` sit between `$tbl_destroy_table/1` and `$tbl_delay_list/1`). The TB1 entries are appended after them. TB2's entries (relay TB2d): the
# worklist predicates and `$tbl_wkl_work/6` (NDET) after `$tbl_wkl_add_answer/4`'s place, the completion and freeing
# predicates after `$tbl_table_pi/2`'s, the inspection predicates after `$tbl_add_global_delays/2`'s (at the stack: TB2's after TB1's); `$tbl_pop_worklist/2`
# first, `$tbl_wkl_table/2` after `$tbl_incomplete/3`'s place (TB2e).
"pl-tabling.c's registration table (`BeginPredDefs(tabling)`): the ported entries."
const PL_predicates_from_tabling = (
    PL_extension("\$tbl_wkl_negative", 1, pl_tbl_wkl_negative1_va, PL_FA_VARARGS),
    PL_extension("\$tbl_wkl_is_false", 1, pl_tbl_wkl_is_false1_va, PL_FA_VARARGS),
    PL_extension("\$tbl_pop_worklist", 2, pl_tbl_pop_worklist2_va, PL_FA_VARARGS),
    PL_extension("\$tbl_wkl_add_answer", 4, pl_tbl_wkl_add_answer4_va, PL_FA_VARARGS),
    PL_extension("\$tbl_wkl_make_follower", 1, pl_tbl_wkl_make_follower1_va, PL_FA_VARARGS),
    PL_extension(
        "\$tbl_wkl_add_suspension", 2, pl_tbl_wkl_add_suspension2_va, PL_FA_VARARGS
    ),
    PL_extension(
        "\$tbl_wkl_add_suspension", 3, pl_tbl_wkl_add_suspension3_va, PL_FA_VARARGS
    ),
    PL_extension("\$tbl_wkl_done", 1, pl_tbl_wkl_done1_va, PL_FA_VARARGS),
    PL_extension("\$tbl_wkl_answer_trie", 2, pl_tbl_wkl_answer_trie2_va, PL_FA_VARARGS),
    PL_extension(
        "\$tbl_wkl_work", 6, pl_tbl_wkl_work6_va, PL_FA_NONDETERMINISTIC | PL_FA_VARARGS
    ),
    PL_extension(
        "\$tbl_table_complete_all", 3, pl_tbl_table_complete_all3_va, PL_FA_VARARGS
    ),
    PL_extension("\$tbl_leader_complete", 4, pl_tbl_leader_complete4_va, PL_FA_VARARGS),
    PL_extension("\$tbl_free_component", 1, pl_tbl_free_component1_va, PL_FA_VARARGS),
    PL_extension("\$tbl_table_discard_all", 1, pl_tbl_table_discard_all1_va, PL_FA_VARARGS),
    PL_extension("\$tbl_trienode", 1, pl_tbl_trienode1_va, PL_FA_VARARGS),
    PL_extension("\$tbl_is_trienode", 1, pl_tbl_is_trienode1_va, PL_FA_VARARGS),
    PL_extension(
        "\$tbl_answer", 3, pl_tbl_answer3_va, PL_FA_NONDETERMINISTIC | PL_FA_VARARGS
    ),
    PL_extension(
        "\$tbl_answer_c", 4, pl_tbl_answer_c4_va, PL_FA_NONDETERMINISTIC | PL_FA_VARARGS
    ),
    PL_extension(
        "\$tbl_answer_dl", 3, pl_tbl_answer_dl3_va, PL_FA_NONDETERMINISTIC | PL_FA_VARARGS
    ),
    PL_extension(
        "\$tbl_answer_dl", 4, pl_tbl_answer_dl4_va, PL_FA_NONDETERMINISTIC | PL_FA_VARARGS
    ),
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
    PL_extension("\$is_answer_trie", 2, pl_is_answer_trie2_va, PL_FA_VARARGS),
    PL_extension("\$tbl_scc", 1, pl_tbl_scc1_va, PL_FA_VARARGS),
    PL_extension("\$tbl_scc_data", 2, pl_tbl_scc_data2_va, PL_FA_VARARGS),
    PL_extension("\$tbl_worklist_data", 2, pl_tbl_worklist_data2_va, PL_FA_VARARGS),
    PL_extension("\$tbl_wkl_table", 2, pl_tbl_wkl_table2_va, PL_FA_VARARGS),
    PL_extension("\$idg_set_current", 2, pl_idg_set_current2_va, PL_FA_VARARGS),
    PL_extension("\$idg_add_edge", 1, pl_idg_add_edge1_va, PL_FA_VARARGS),
    PL_extension("\$tbl_delay_list", 1, pl_tbl_delay_list1_va, PL_FA_VARARGS),
    PL_extension("\$tbl_set_delay_list", 1, pl_tbl_set_delay_list1_va, PL_FA_VARARGS),
    PL_extension("\$tbl_add_global_delays", 2, pl_tbl_add_global_delays2_va, PL_FA_VARARGS),
    PL_extension(
        "\$tbl_answer_update_dl",
        2,
        pl_tbl_answer_update_dl2_va,
        PL_FA_NONDETERMINISTIC | PL_FA_VARARGS
    ),
    PL_extension(
        "\$tbl_answer_update_dl",
        3,
        pl_tbl_answer_update_dl3_va,
        PL_FA_NONDETERMINISTIC | PL_FA_VARARGS
    ),
    PL_extension("\$tbl_force_truth_value", 3, pl_tbl_force_truth_value3_va, PL_FA_VARARGS),
    PL_extension(
        "\$tbl_set_answer_completed", 1, pl_tbl_set_answer_completed1_va, PL_FA_VARARGS
    ),
    PL_extension(
        "\$tbl_is_answer_completed", 1, pl_tbl_is_answer_completed1_va, PL_FA_VARARGS
    )
)
