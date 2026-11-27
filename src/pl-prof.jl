# UPSTREAM: swipl-devel src/pl-prof.c @ af9e2e7ed0be
# UPSTREAM: swipl-devel src/pl-prof.h @ af9e2e7ed0be
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2026, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# allow-new-artifact: a port of the pin's src/pl-prof.c, read from the pin (git show 18168e62) for this file
#
# PROF1 (pl-prof.c), lane F, FIRST HALF: the data layer of the profiler: the call tree (`call_node`, src/pl-incl.jl), the status
# atoms, the node pointer, and the foreign predicates that read it ('$prof_sibling_of'/2, '$prof_node'/8,
# '$prof_procedure_data'/9, '$prof_procedures'/1, '$prof_statistics'/9) or reset it (reset_profiler/0), with `profiler/2` and
# `'$profile'/4`. SYNC3 (swipl-devel af9e2e7e): the global stack accounting (`prof_mem`, `mem(Allocated, ..)` in the summaries), the
# index of the tree by handle (`get_prof_index`: collecting all data was quadratic in the size of the tree), `'$prof_procedures'/1`.
#
# THE COLLECTION ITSELF IS A NAMED REFUSAL (NotPortedError, step PROF1). Upstream samples with SIGPROF/SIGALRM and `setitimer`
# (pl-prof.c:759-816 `startProfiler`, `sig_profile`), reads the thread's CPU time (`ThreadCPUTime`, `prof_thread_cpu_ns`), the
# TSC or the OS monotonic clock for the exact modes (pl-prof.c:57-153, 274-545), and charges nodes from the VM's call, exit and
# fail ports (`profCall`, `profExit`, `profFail`, `profResumeParent`, pl-prof.c:1600-1840, called from the VM). None of these
# exists in this kernel, so `startProfiler`, `activateProfiler`, `'$prof_exact_ok'/1`, `'$prof_clock_cost'/1` and the foreign
# API (`PL_register_profile_type`, `PL_prof_call`, `PL_prof_exit`) refuse by name; the tree stays empty unless a test builds
# one (`new_call_node!`, ORIGINAL). `profiler/2` reports `false`, `'$profile'/4` sets its options, resets the data and refuses
# at the start, as upstream's first statements run.
#
# DIVERGES (file-wide):
#   1. NODE POINTERS: see src/pl-incl.jl (an `Int` index into `ld.profile.node_table`).
#   2. NO SIGNALS: `sumProfile`'s `PL_handle_signals` has no twin; `GD->profile.thread` (which thread is profiled) has no field,
#      the profiler being startable by none.
#   3. `resetProfiler`'s `prof_clear_stacks` (a walk of the VM's frames clearing `fr->prof_node`) has no twin: no frame of this
#      VM carries a profile node.
#   4. `get_def`: `get_procedure(..., GP_FIND|GP_NAMEARITY|GP_TYPE_QUIET)` is `get_procedure_namearity` (src/pl-proc.jl), which has no
#      quiet flag; GP_TYPE_QUIET only silences the "no Name/Arity" error in upstream's get_functor (pl-proc.c:661), so `get_def`
#      checks for `/`/2 or `//`/2 first and fails without an error, every other error (bad name, arity) is raised as upstream.
#   6. NO GC (SYNC3): `prof_mem_clock` adds `LD->gc.stats.totals.global_gained` to the global stack in use; this kernel has no
#      stack garbage collector (statistics/2 reports 0 for it), so `prof_gc_global_gained` and `prof_gc_collections` are 0.
#   5. MEMORY: no `allocHeap`, no `releaseModule` (`prof_release_def`: no module GC), the `prof_ref` chains are vectors
#      (new references are pushed at the end and unified from the end, upstream's order of `r->next = callers; callers = r`).

"Raise the named refusal of a collection entry point (step PROF1)."
# No upstream twin (kept as a comment, not a header line): the refusal every collection entry point raises (step PROF1).
function _prof_refuse(
    ld::PL_local_data{T}, culprit::Symbol, what::String
)::Union{} where {T}
    throw(NotPortedError{T}(mk_sym(T, culprit), what, "PROF1"))
end

# ORIGINAL: upstream's `allocHeapOrHalt` + `memset` of a node; its pointer is the index `ld.profile.node_table` gives it.
"Allocate a call node for `handle` of profile type `type`; its pointer (an `Int` index, never 0)."
function new_call_node!(
    ld::PL_local_data{T}, handle::Union{Nothing, Definition{T}}, type::Int
)::Int where {T}
    push!(ld.profile.node_table, call_node{T}(handle, type))
    ld.profile.nodes += 1
    return length(ld.profile.node_table)
end

# ORIGINAL: `n->magic == PROFNODE_MAGIC` on a pointer: the node at `ptr`, or `nothing` (0, out of range, freed).
"The live call node a pointer indexes, or `nothing`."
function prof_node_at(
    ld::PL_local_data{T}, ptr::Int
)::Union{Nothing, call_node{T}} where {T}
    (ptr < 1 || ptr > length(ld.profile.node_table)) && return nothing
    n = ld.profile.node_table[ptr]
    (n === nothing || n.magic != PROFNODE_MAGIC) && return nothing
    return n
end

# PORT: pl-prof.c get_prof_status
"The `prof_status` the atom `t` names (`false`, `true`, `cputime`, `walltime`, `exact_walltime`, `exact_cputime`), or `nothing` with an error raised (pl-prof.c)."
function get_prof_status(ld::PL_local_data{T}, t::term_t)::Union{Nothing, Int} where {T}
    a = PL_get_atom_ex(ld, t)
    a === nothing && return nothing
    k = sym_key(a)
    k == sym_key(mk_sym(T, Symbol("false"))) && return PROF_INACTIVE
    (k == sym_key(mk_sym(T, Symbol("true"))) || k == sym_key(mk_sym(T, :cputime))) &&
        return PROF_CPU
    k == sym_key(mk_sym(T, :walltime)) && return PROF_WALL
    k == sym_key(mk_sym(T, :exact_walltime)) && return PROF_WALL_EXACT
    k == sym_key(mk_sym(T, :exact_cputime)) && return PROF_CPU_EXACT
    PL_domain_error(ld, "profile_status", t)
    return nothing
end

# PORT: pl-prof.c prof_status_atom
"The atom naming the `prof_status` `s` (pl-prof.c)."
function prof_status_atom(::Type{T}, s::Int)::T where {T}
    s == PROF_CPU && return mk_sym(T, :cputime)
    s == PROF_WALL && return mk_sym(T, :walltime)
    s == PROF_WALL_EXACT && return mk_sym(T, :exact_walltime)
    s == PROF_CPU_EXACT && return mk_sym(T, :exact_cputime)
    return mk_sym(T, Symbol("false"))
end

# PORT: pl-prof.c get_node
"The node pointer in `'\$prof_node'(Ptr)` (`t`), or `nothing` with `type_error(profile_node, T)` raised (pl-prof.c)."
function get_node(ld::PL_local_data{T}, t::term_t)::Union{Nothing, Int} where {T}
    if PL_is_functor(ld, t, mk_sym(T, Symbol("\$prof_node")), 1)        # FUNCTOR_dprof_node1
        a = PL_new_term_ref(ld)
        _PL_get_arg(ld, 1, t, a)
        ptr = PL_get_int64(ld, a)                       # PL_get_pointer(a, &ptr)
        if ptr !== nothing && prof_node_at(ld, ptr) !== nothing
            return ptr
        end
    end
    PL_type_error(ld, "profile_node", t)               # PL_error(NULL, 0, NULL, ERR_TYPE, ATOM_profile_node, t)
    return nothing
end

# PORT: pl-prof.c unify_node
"Unify `t` with `'\$prof_node'(Ptr)` for the node `ptr` (pl-prof.c)."
function unify_node(ld::PL_local_data{T}, t::term_t, ptr::Int)::Bool where {T}
    PL_unify_functor(ld, t, mk_sym(T, Symbol("\$prof_node")), 1) || return false
    a = PL_new_term_ref(ld)
    _PL_get_arg(ld, 1, t, a)
    return PL_unify_int64(ld, a, ptr)                   # PL_POINTER
end

# PORT: pl-prof.c prof_sibling_of as pl_prof_sibling_of2_va
# (PRED_IMPL("$prof_sibling_of", 2, prof_sibling_of, PL_FA_NONDETERMINISTIC))
# DIVERGES: file-wide 1: the REDO pointer is the sibling's node pointer.
"""
`'\$prof_sibling_of'(?Child, ?Parent)`: generate the call hierarchy; with Parent `-`, the roots (pl-prof.c).
"""
function pl_prof_sibling_of2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    ctl = PL_foreign_control(PL__ctx)
    sibling = 0
    if ctl == FRG_FIRST_CALL
        if !PL_is_variable(ld, A1)
            s = get_node(ld, A1)
            if s !== nothing
                par = prof_node_at(ld, s)::call_node{T}
                if par.parent != 0
                    return unify_node(ld, A2, par.parent) ? FTRUE : FFALSE
                end
            end
            return FFALSE
        else
            a = PL_get_atom(ld, A2)
            if a !== nothing && sym_key(a) == sym_key(mk_sym(T, :(-)))
                sibling = ld.profile.roots
            else
                p = get_node(ld, A2)
                p === nothing && return FFALSE
                sibling = (prof_node_at(ld, p)::call_node{T}).siblings
            end
        end
        sibling == 0 && return FFALSE
    elseif ctl == FRG_REDO
        sibling = PL_foreign_context_address(PL__ctx)   # CTX_PTR
    else                                                # FRG_CUTTED
        return FTRUE
    end
    unify_node(ld, A1, sibling) || return FFALSE
    nxt = (prof_node_at(ld, sibling)::call_node{T}).next
    nxt != 0 && return PL_retry_address(nxt)            # ForeignRedoPtr(sibling->next)
    return FTRUE
end

# PORT: pl-prof.c identify_def
"Unify `t` with the definition `handle` as `Module:Name/Arity` (pl-prof.c: the type's `unify`)."
function identify_def(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t, handle::Definition{T}
)::Bool where {T}
    return unify_definition(
        gd, ld, MODULE_user(gd), t, handle, 0, GP_QUALIFY | GP_NAMEARITY
    )
end

# PORT: pl-prof.c unify_node_id
# DIVERGES: file-wide 1: the one profile type is the default one, whose `unify` is `identify_def`.
"Unify `t` with the identity of the node `n` (pl-prof.c)."
function unify_node_id(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t, n::call_node{T}
)::Bool where {T}
    return identify_def(gd, ld, t, n.handle::Definition{T})
end

# PORT: pl-prof.c prof_node as pl_prof_node8_va
# (PRED_IMPL("$prof_node", 8, prof_node, 0))
"`'\$prof_node'(+Node, -Pred, -Calls, -Redos, -Exits, -Recursive, -Ticks, -SiblingTicks)` (pl-prof.c)."
function pl_prof_node8_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    ptr = get_node(ld, PL__t0)
    ptr === nothing && return FFALSE
    n = prof_node_at(ld, ptr)::call_node{T}
    collectSiblingsTime(ld)
    return if (
        unify_node_id(gd, ld, PL__t0 + 1, n) &&
        PL_unify_int64(ld, PL__t0 + 2, n.calls) &&
        PL_unify_int64(ld, PL__t0 + 3, n.exits + n.fails - n.calls) &&
        PL_unify_int64(ld, PL__t0 + 4, n.exits) &&
        PL_unify_int64(ld, PL__t0 + 5, n.recur) &&
        PL_unify_int64(ld, PL__t0 + 6, n.ticks) &&
        PL_unify_int64(ld, PL__t0 + 7, n.sibling_ticks)
    )
        FTRUE
    else
        FFALSE
    end
end

# The kinds of a reference: a real definition, or one of the two special handles (pl-prof.c: `(Definition)0` and
# `(Definition)1`); the `handle` of the last two is `nothing`. `PROF_REF_DEF` has no upstream twin.
const PROF_REF_DEF = 0
# PORT: pl-prof.c DEF_SPONTANEOUS as PROF_REF_SPONTANEOUS
# DIVERGES: the special handle is a kind of a reference, its `handle` being `nothing` then.
const PROF_REF_SPONTANEOUS = 1
# PORT: pl-prof.c DEF_RECURSIVE as PROF_REF_RECURSIVE
# DIVERGES: the special handle is a kind of a reference, its `handle` being `nothing` then.
const PROF_REF_RECURSIVE = 2

# PORT: pl-prof.c prof_ref
"A caller or callee of a procedure in the summary (pl-prof.c `struct prof_ref`)."
mutable struct prof_ref{T}
    kind::Int                                   # PROF_REF_DEF, _SPONTANEOUS or _RECURSIVE
    handle::Union{Nothing, Definition{T}}       # Procedure handle
    type::Int
    cycle::Int
    ticks::Int
    sibling_ticks::Int
    mem::prof_mem
    sibling_mem::prof_mem
    calls::Int                                  # calls to/from this predicate
    redos::Int                                  # redos to/from this predicate
    exits::Int                                  # exits to/from this predicate
end

# PORT: pl-prof.c node_sum
"The summary of one procedure over the call tree (pl-prof.c `node_sum`)."
mutable struct node_sum{T}
    ticks::Int
    sibling_ticks::Int
    mem::prof_mem
    sibling_mem::prof_mem
    calls::Int
    redos::Int
    exits::Int
    recur::Int
    callers::Vector{prof_ref{T}}
    callees::Vector{prof_ref{T}}
end
node_sum{T}() where {T} =
    node_sum{T}(0, 0, prof_mem(), prof_mem(), 0, 0, 0, 0, prof_ref{T}[], prof_ref{T}[])

# PORT: pl-prof.c node_redos
"The redos of a node: its exits and fails beyond its calls (a call still running counts none; pl-prof.c)."
function node_redos(n::call_node{T})::Int where {T}
    left = n.exits + n.fails
    return left > n.calls ? left - n.calls : 0
end

# PORT: pl-prof.c add_parent_ref
"Add the node `self` to the callers of `sum`: `handle` (`kind`) its parent (pl-prof.c)."
function add_parent_ref!(
    sum::node_sum{T}, self::call_node{T}, kind::Int, handle::Union{Nothing, Definition{T}},
    type::Int, cycle::Int
)::Nothing where {T}
    sum.calls += self.calls
    sum.redos += node_redos(self)
    sum.exits += self.exits

    for r in sum.callers
        if r.kind == kind && r.handle === handle && r.cycle == cycle
            r.calls += self.calls
            r.redos += node_redos(self)
            r.exits += self.exits
            r.ticks += self.ticks
            r.sibling_ticks += self.sibling_ticks
            add_prof_mem(r.mem, self.mem)
            add_prof_mem(r.sibling_mem, self.sibling_mem)
            return nothing
        end
    end

    push!(
        sum.callers,
        prof_ref{T}(
            kind,
            handle,
            type,
            cycle,
            self.ticks,
            self.sibling_ticks,
            copy(self.mem),
            copy(self.sibling_mem),
            self.calls,
            node_redos(self),
            self.exits
        )
    )
    return nothing
end

# PORT: pl-prof.c add_recursive_ref
"Add `count` recursive calls to the callers of `sum` (pl-prof.c)."
function add_recursive_ref!(sum::node_sum{T}, count::Int, cycle::Int)::Nothing where {T}
    for r in sum.callers
        if r.kind == PROF_REF_RECURSIVE && r.cycle == cycle
            r.calls += count
            return nothing
        end
    end
    push!(
        sum.callers,
        prof_ref{T}(
            PROF_REF_RECURSIVE, nothing, 0, cycle, 0, 0, prof_mem(), prof_mem(), count, 0, 0
        )
    )
    return nothing
end

# PORT: pl-prof.c add_sibling_ref
"Add the node `sibling` to the callees of `sum` (pl-prof.c)."
function add_sibling_ref!(
    sum::node_sum{T}, sibling::call_node{T}, cycle::Int
)::Nothing where {T}
    for r in sum.callees
        if r.kind == PROF_REF_DEF && r.handle === sibling.handle && r.cycle == cycle
            r.calls += sibling.calls
            r.redos += node_redos(sibling)
            r.exits += sibling.exits
            r.ticks += sibling.ticks
            r.sibling_ticks += sibling.sibling_ticks
            add_prof_mem(r.mem, sibling.mem)
            add_prof_mem(r.sibling_mem, sibling.sibling_mem)
            return nothing
        end
    end
    push!(
        sum.callees,
        prof_ref{T}(
            PROF_REF_DEF, sibling.handle, sibling.type, cycle, sibling.ticks,
            sibling.sibling_ticks, copy(sibling.mem), copy(sibling.sibling_mem),
            sibling.calls, node_redos(sibling), sibling.exits
        )
    )
    return nothing
end

# prof_index (pl-prof.c; its PORT marker and the type are in src/pl-incl.jl): `$prof_procedure_data/9` sums the nodes of one handle. Walking the whole call tree for each predicate makes collecting all data
# quadratic, so upstream indexes the tree once: for each handle the nodes in depth-first order and, for each node, the number of its
# ancestors with the same handle (`seen`, the cycle). The index only depends on the shape of the tree, which only changes when a
# node is added or all nodes are freed: it is valid as long as `LD->profile.nodes` is unchanged. The types are in src/pl-incl.jl.

# PORT: pl-prof.c free_prof_index
# DIVERGES: file-wide 5: the memory is the garbage collector's; the function empties the containers.
"Free the index `idx` (pl-prof.c)."
function free_prof_index(idx::Union{Nothing, prof_index{T}})::Nothing where {T}
    if idx !== nothing
        empty!(idx.all)
        empty!(idx.table)
    end
    return nothing
end

# PORT: pl-prof.c handle_nodes
"The `prof_handle_nodes` of `handle` in `idx`, created if there is none (pl-prof.c)."
function handle_nodes(
    idx::prof_index{T}, handle::Union{Nothing, Definition{T}}
)::prof_handle_nodes{T} where {T}
    h = get(idx.table, handle, nothing)
    if h === nothing
        h = prof_handle_nodes{T}()
        push!(idx.all, h)
        idx.table[handle] = h
    end
    return h
end

# PORT: pl-prof.c add_occurrence
# DIVERGES: file-wide 5: the vector grows by itself; no out-of-memory result (upstream: `realloc` failing).
"Add the node `n` to the occurrences of `h`, with the current depth as its `seen` (pl-prof.c)."
function add_occurrence(h::prof_handle_nodes{T}, n::call_node{T})::Bool where {T}
    push!(h.occurrences, prof_occurrence{T}(n, h.depth))
    return true
end

# PORT: pl-prof.c get_prof_index
# DIVERGES: file-wide 2: upstream checks for signals every 64K nodes (`PL_handle_signals`) and returns NULL with an exception; and
# `PL_no_memory`: the function returns the index.
"Get the index of the call tree, building it if the tree changed (pl-prof.c)."
function get_prof_index(ld::PL_local_data{T})::prof_index{T} where {T}
    idx = ld.profile.index
    if idx !== nothing && idx.nodes == ld.profile.nodes
        return idx
    end

    free_prof_index(idx)
    ld.profile.index = nothing
    idx = prof_index{T}()

    rootp = ld.profile.roots
    while rootp != 0
        root = prof_node_at(ld, rootp)::call_node{T}
        n = root
        done = false

        while !done
            h = handle_nodes(idx, n.handle)                     # enter n
            add_occurrence(h, n)
            h.depth += 1
            if n.siblings != 0
                n = prof_node_at(ld, n.siblings)::call_node{T}
                continue
            end

            while true                                          # leave n
                h = idx.table[n.handle]
                h.depth -= 1
                if n === root
                    done = true
                    break
                end
                if n.next != 0
                    n = prof_node_at(ld, n.next)::call_node{T}
                    break
                end
                n = prof_node_at(ld, n.parent)::call_node{T}
            end
        end
        rootp = root.next
    end

    idx.nodes = ld.profile.nodes
    ld.profile.index = idx
    return idx
end

# PORT: pl-prof.c sum_node
# DIVERGES: `ld` is passed to follow the node pointers (upstream's are C pointers).
"Add the node `n`, with `seen` ancestors of the same handle, to the summary `sum` (pl-prof.c)."
function sum_node(
    ld::PL_local_data{T}, n::call_node{T}, sum::node_sum{T}, seen::Int
)::Nothing where {T}
    sum.ticks += n.ticks
    add_prof_mem(sum.mem, n.mem)
    if seen == 0
        sum.sibling_ticks += n.sibling_ticks
        add_prof_mem(sum.sibling_mem, n.sibling_mem)
    else                                                # nested: n's ticks are in the outer siblings
        sum.sibling_ticks -= n.ticks
        sub_prof_mem(sum.sibling_mem, n.mem)
    end

    if n.parent != 0
        p = prof_node_at(ld, n.parent)::call_node{T}
        add_parent_ref!(sum, n, PROF_REF_DEF, p.handle, p.type, seen)
    else
        add_parent_ref!(sum, n, PROF_REF_SPONTANEOUS, nothing, 0, seen)
    end

    n.recur != 0 && add_recursive_ref!(sum, n.recur, seen)

    s = n.siblings
    while s != 0
        sn = prof_node_at(ld, s)::call_node{T}
        add_sibling_ref!(sum, sn, seen)
        s = sn.next
    end
    return nothing
end

# ORIGINAL: the `PL_FUNCTOR, FUNCTOR_mem4, PL_INT64 x 4` of upstream's `PL_unify_term` calls: unify `t` with `mem(A, B, C, D)`.
"Unify `t` with `mem(A, B, C, D)` (the four counters of a global stack accounting; pl-prof.c `FUNCTOR_mem4`)."
function prof_unify_mem4(
    ld::PL_local_data{T}, t::term_t, A::Int, B::Int, C::Int, D::Int
)::Bool where {T}
    PL_unify_functor(ld, t, mk_sym(T, :mem), 4) || return false
    a = PL_new_term_ref(ld)
    vals = (A, B, C, D)
    for i in 1:4
        _PL_get_arg(ld, i, t, a)
        PL_unify_int64(ld, a, vals[i]) || return false
    end
    return true
end

# PORT: pl-prof.c unify_relatives
"Unify the list `list` with the `node/8` terms of the references `refs` (pl-prof.c)."
function unify_relatives(
    gd::PL_global_data{T}, ld::PL_local_data{T}, list::term_t, refs::Vector{prof_ref{T}}
)::Bool where {T}
    tail = PL_copy_term_ref(ld, list)
    head = PL_new_term_ref(ld)
    tmp = PL_new_term_ref(ld)

    for r in Iterators.reverse(refs)                    # upstream's chain: the last added first
        PL_unify_list(ld, tail, head, tail) || return false

        PL_put_variable(ld, tmp)
        rc = if r.kind == PROF_REF_SPONTANEOUS
            PL_unify_atom(ld, tmp, mk_sym(T, Symbol("<spontaneous>")))
        elseif r.kind == PROF_REF_RECURSIVE
            PL_unify_atom(ld, tmp, mk_sym(T, Symbol("<recursive>")))
        else
            identify_def(gd, ld, tmp, r.handle::Definition{T})      # (*r->type->unify)(tmp, r->handle)
        end

        rc || return false
        PL_unify_functor(ld, head, mk_sym(T, :node), 8) || return false     # FUNCTOR_node8
        a = PL_new_term_ref(ld)
        vals = (nothing, r.cycle, r.ticks, r.sibling_ticks, r.calls, r.redos, r.exits)
        for i in 1:7
            _PL_get_arg(ld, i, head, a)
            ok = i == 1 ? PL_unify(ld, a, tmp) : PL_unify_int64(ld, a, vals[i]::Int)
            ok || return false
        end
        _PL_get_arg(ld, 8, head, a)
        prof_unify_mem4(
            ld, a, r.mem.allocated, r.sibling_mem.allocated, r.mem.discarded,
            r.sibling_mem.discarded
        ) || return false
    end

    return PL_unify_nil(ld, tail)
end

# PORT: pl-prof.c get_def
# DIVERGES: file-wide 4.
"The definition the `Name/Arity` in `t` names, or `nothing` (a failure; pl-prof.c)."
function get_def(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t
)::Union{Nothing, Definition{T}} where {T}
    head = PL_new_term_ref(ld)
    ok, _ = PL_strip_module(gd, ld, t, MODULE_user(gd).index, head)
    ok || return nothing
    if !(
        PL_is_functor(ld, head, mk_sym(T, :/), 2) ||
        PL_is_functor(ld, head, mk_sym(T, :(//)), 2)
    )
        return nothing                                  # GP_TYPE_QUIET: no indicator at all fails without an error
    end
    proc = get_procedure_namearity(gd, ld, t, MODULE_user(gd), GP_FIND | GP_NAMEARITY)
    proc === nothing && return nothing                  # a bad name or arity keeps its error, as upstream's get_functor
    return proc.definition
end

# PORT: pl-prof.c get_handle
# DIVERGES: file-wide 1: the type table holds the default type only.
"The profile handle `t` names, offered to every registered type in turn (pl-prof.c)."
get_handle(gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t) where {T} =
    get_def(gd, ld, t)

# PORT: pl-prof.c prof_procedure_data as pl_prof_procedure_data9_va
# (PRED_IMPL("$prof_procedure_data", 9, prof_procedure_data, PL_FA_TRANSPARENT))
# DIVERGES: the context module of the transparent predicate is `user` (as compile_predicates/1: the caller's context is left out).
# DIVERGES: file-wide 2: upstream checks for signals every 64K occurrences (`PL_handle_signals`, freeing the relatives when cut short).
"`'\$prof_procedure_data'(+PI, -Ticks, -TicksSiblings, -Calls, -Redos, -Exits, -Callers, -Callees, -Memory)` (pl-prof.c); `Memory` is `mem(Allocated, AllocatedSiblings, Discarded, DiscardedSiblings)`, in bytes of global stack."
function pl_prof_procedure_data9_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    handle = get_handle(gd, ld, PL__t0)
    handle === nothing && return FFALSE
    collectSiblingsTime(ld)
    idx = get_prof_index(ld)
    h = get(idx.table, handle, nothing)
    h === nothing && return FFALSE                      # nothing known about this one

    sum = node_sum{T}()
    for o in h.occurrences
        sum_node(ld, o.node, sum, o.seen)
    end

    return if (
        PL_unify_int64(ld, PL__t0 + 1, sum.ticks) &&
        PL_unify_int64(ld, PL__t0 + 2, sum.sibling_ticks) &&
        PL_unify_int64(ld, PL__t0 + 3, sum.calls) &&
        PL_unify_int64(ld, PL__t0 + 4, sum.redos) &&
        PL_unify_int64(ld, PL__t0 + 5, sum.exits) &&
        unify_relatives(gd, ld, PL__t0 + 6, sum.callers) &&
        unify_relatives(gd, ld, PL__t0 + 7, sum.callees) &&
        prof_unify_mem4(
            ld, PL__t0 + 8, sum.mem.allocated, sum.sibling_mem.allocated, sum.mem.discarded,
            sum.sibling_mem.discarded
        )
    )
        FTRUE
    else
        FFALSE
    end
end

# PORT: pl-prof.c prof_statistics as pl_prof_statistics9_va
# (PRED_IMPL("$prof_statistics", 9, prof_statistics, 0))
"`'\$prof_statistics'(-Samples, -Ticks, -AccountingTicks, -Time, -Nodes, -Period, -Ports, -Mode, -Memory)` (pl-prof.c); `Memory` is `mem(Allocated, Discarded, GCReclaimed, GCCount)`: the global stack (bytes) allocated, discarded by backtracking and reclaimed by GC while profiling and the number of garbage collections."
function pl_prof_statistics9_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    p = ld.profile
    ports = if p.ports_control == PROFC_FALSE
        Symbol("false")
    elseif p.ports_control == PROFC_TRUE
        Symbol("true")
    else
        :classic
    end
    return if (
        PL_unify_int64(ld, PL__t0, p.samples) &&
        PL_unify_int64(ld, PL__t0 + 1, p.ticks) &&
        PL_unify_int64(ld, PL__t0 + 2, p.accounting_ticks) &&
        PL_unify_float(ld, PL__t0 + 3, p.time) &&
        PL_unify_int64(ld, PL__t0 + 4, p.nodes) &&
        PL_unify_integer(ld, PL__t0 + 5, p.sample_period) &&
        PL_unify_atom(ld, PL__t0 + 6, mk_sym(T, ports)) &&
        PL_unify_atom(ld, PL__t0 + 7, prof_status_atom(T, p.mode)) &&
        prof_unify_mem4(
            ld, PL__t0 + 8, p.mem.allocated, p.mem.discarded, p.mem.gc_reclaimed,
            p.mem.gc_count
        )
    )
        FTRUE
    else
        FFALSE
    end
end

# PORT: pl-prof.c prof_procedures as pl_prof_procedures1_va
# (PRED_IMPL("$prof_procedures", 1, prof_procedures, 0))
"`'\$prof_procedures'(-Ids:list)`: Ids holds the identifier of each procedure or other profiled object that has a node in the call tree, in no particular order (pl-prof.c)."
function pl_prof_procedures1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    tail = PL_copy_term_ref(ld, PL__t0)
    head = PL_new_term_ref(ld)
    idx = get_prof_index(ld)

    for h in Iterators.reverse(idx.all)                 # upstream's chain: the last created first
        if !(
            PL_unify_list(ld, tail, head, tail) &&
            unify_node_id(gd, ld, head, h.occurrences[1].node)
        )
            return FFALSE
        end
    end

    return PL_unify_nil(ld, tail) ? FTRUE : FFALSE
end

# PORT: pl-prof.c collectSiblingsNode
# DIVERGES: the node links are pointers (indexes): `prof_node_at` follows them. The `memset` of a `sibling_mem` is a fresh `prof_mem`.
"Compute `sibling_ticks` and `sibling_mem` of the tree below `root`: the sums of the ticks and memory of all nodes below a node; a depth-first walk without recursion: each node adds its totals to its parent when we leave it (pl-prof.c)."
function collectSiblingsNode(ld::PL_local_data{T}, root::call_node{T})::Nothing where {T}
    n = root

    root.sibling_ticks = 0
    root.sibling_mem = prof_mem()

    while true
        if n.siblings != 0                              # enter the first child
            n = prof_node_at(ld, n.siblings)::call_node{T}
            n.sibling_ticks = 0
            n.sibling_mem = prof_mem()
            continue
        end

        while true                                      # leave n
            n === root && return nothing
            p = prof_node_at(ld, n.parent)::call_node{T}
            p.sibling_ticks += n.ticks + n.sibling_ticks
            add_prof_mem(p.sibling_mem, n.mem)
            add_prof_mem(p.sibling_mem, n.sibling_mem)
            if n.next != 0                              # enter the next child of p
                n = prof_node_at(ld, n.next)::call_node{T}
                n.sibling_ticks = 0
                n.sibling_mem = prof_mem()
                break
            end
            n = p
        end
    end
end

# PORT: pl-prof.c collectSiblingsTime
"Propagate the leaf ticks up the tree, once until the tree changes (pl-prof.c)."
function collectSiblingsTime(ld::PL_local_data{T})::Nothing where {T}
    if !ld.profile.sum_ok
        n = ld.profile.roots
        while n != 0
            nn = prof_node_at(ld, n)::call_node{T}
            collectSiblingsNode(ld, nn)
            n = nn.next
        end
        ld.profile.sum_ok = true
    end
    return nothing
end

# PORT: pl-prof.c freeProfileNode
# DIVERGES: file-wide 3 and 5 (`prof_release_def`: no module reference to release; the slot keeps `nothing`).
"Free the node `ptr` and its subtree (pl-prof.c)."
function freeProfileNode(ld::PL_local_data{T}, ptr::Int)::Nothing where {T}
    node = prof_node_at(ld, ptr)::call_node{T}
    n = node.siblings
    while n != 0
        nn = prof_node_at(ld, n)::call_node{T}
        nxt = nn.next
        freeProfileNode(ld, n)
        n = nxt
    end
    node.magic = 0
    ld.profile.node_table[ptr] = nothing
    ld.profile.nodes -= 1
    return nothing
end

# PORT: pl-prof.c freeProfileData
"Free the whole call tree (pl-prof.c)."
function freeProfileData(ld::PL_local_data{T})::Nothing where {T}
    n = ld.profile.roots
    ld.profile.roots = 0
    ld.profile.current = 0
    free_prof_index(ld.profile.index)
    ld.profile.index = nothing

    while n != 0
        nxt = (prof_node_at(ld, n)::call_node{T}).next
        freeProfileNode(ld, n)
        n = nxt
    end

    @assert ld.profile.nodes == 0
    empty!(ld.profile.node_table)                       # (no pointer is live: a stale one is a type error)
    return nothing
end

# PORT: pl-prof.c stopProfiler
# DIVERGES (SYNC3): upstream, once the timer is stopped, charges the memory clock and totals the GC of the run before
# `activateProfiler(PROF_INACTIVE)`:
#     prof_mem_charge(LD->profile.current, LD->profile.current);
#     LD->profile.mem.gc_reclaimed += LD->gc.stats.totals.global_gained - LD->profile.mem.gc_start;
#     LD->profile.mem.gc_count     += LD->gc.stats.totals.collections   - LD->profile.mem.gc_count_start;
# not written: the refusal below is raised first (the profiler cannot be started); the later step that lets a profiler run writes
# them, with `prof_mem_charge`, `prof_gc_global_gained` and `prof_gc_collections` (this file).
# DIVERGES: file-wide 2: `GD->profile.thread` has no field and the profiler cannot be started, so an active profiler (reachable
# only by a test that sets `ld.profile.active`) is a named refusal at the clock it would read.
"Stop the profiler: true when it is not running (pl-prof.c)."
function stopProfiler(ld::PL_local_data{T})::Bool where {T}
    if ld.profile.active != PROF_INACTIVE
        _prof_refuse(
            ld,
            :stopProfiler,
            "stopping a running profiler (`ThreadCPUTime`, `prof_charge`, `setitimer`: the profiler cannot be started)"
        )
    end
    return true
end

# PORT: pl-prof.c activateProfiler
# DIVERGES (SYNC3): upstream (a) calls `disableProcedureGC()` (pl-proc.c: the profiler keeps `Definition` pointers, so procedures
# created at run time are not collected after profiling once) for `active != PROF_INACTIVE`, before it takes `L_THREAD`; this kernel
# has no procedure GC, so there is nothing to disable; (b) in the activation branch, after `LD->profile.mode = active`, sets
#     LD->profile.mem.last           = prof_mem_clock();
#     LD->profile.mem.gc_start       = LD->gc.stats.totals.global_gained;
#     LD->profile.mem.gc_count_start = LD->gc.stats.totals.collections;
# (b) is not written: the refusal below is raised first; the later step that lets a profiler run writes it with
# `prof_mem_clock`, `prof_gc_global_gained` and `prof_gc_collections` (this file).
"Mark the profiler active: refused by name, the profiler's clocks and signals have no equivalent (pl-prof.c:549-630)."
function activateProfiler(ld::PL_local_data{T}, active::Int)::Bool where {T}
    _prof_refuse(
        ld,
        :activateProfiler,
        "activating the profiler (the thread CPU clock, the TSC, `GD->profile.thread`)"
    )
end

# PORT: pl-prof.c startProfiler
# DIVERGES: refused by name after the statement that precedes the exact-mode branch (the sample period default).
"Start the profiler in mode `how`: refused by name, SIGPROF/SIGALRM and `setitimer` have no equivalent (pl-prof.c:759-800)."
function startProfiler(ld::PL_local_data{T}, how::Int)::Bool where {T}
    if !PROF_IS_EXACT(how) && ld.profile.sample_period == 0         # profiler/2 without $profile/4
        ld.profile.sample_period = DEFAULT_SAMPLE_PERIOD
    end
    _prof_refuse(
        ld,
        :startProfiler,
        "starting the profiler (SIGPROF/SIGALRM, `setitimer`, the exact clocks)"
    )
end

# PORT: pl-prof.c resetProfiler
# DIVERGES: file-wide 3 (`prof_clear_stacks`, `unmark_stacks` and the `LD->gc` counters' asserts have no twin).
"Reset the profiler: stop it, free the call tree and the counters (pl-prof.c); true."
function resetProfiler(ld::PL_local_data{T})::Bool where {T}
    if ld.profile.active != PROF_INACTIVE                   # do not stop another thread
        stopProfiler(ld)
    end

    freeProfileData(ld)
    ld.profile.samples = 0
    ld.profile.ticks = 0
    ld.profile.accounting_ticks = 0
    ld.profile.time = 0.0
    ld.profile.mem = ld_profile_mem()                       # memset(&LD->profile.mem, 0, ..)
    ld.profile.mode = PROF_INACTIVE
    ld.profile.accounting = false

    return true
end

# PORT: pl-prof.c reset_profiler as pl_reset_profiler0_va
# (PRED_IMPL("reset_profiler", 0, reset_profiler, 0))
"`reset_profiler`: free the profile data (pl-prof.c); true."
function pl_reset_profiler0_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    resetProfiler(ld)
    return FTRUE
end

# PORT: pl-prof.c profile
# DIVERGES: `HAS_LD` is true (one engine); the function is the sampler's tick, which nothing calls (no timer thread).
"Tick the profiler by `count` nanoseconds: the leaf node of the call tree gets them, or the accounting (pl-prof.c `profile`)."
function profile!(ld::PL_local_data{T}, count::Int)::Nothing where {T}
    ld.profile.samples += 1
    ld.profile.ticks += count

    if ld.profile.accounting                            # we are updating nodes
        ld.profile.accounting_ticks += count
    else
        node = prof_node_at(ld, ld.profile.current)
        if node !== nothing
            node.ticks += count
        end
    end
    return nothing
end

# PORT: pl-prof.c profiler as pl_profiler2_va
# (PRED_IMPL("profiler", 2, profiler, 0))
# DIVERGES: `PL_compare` has no `CMP_ERROR` result here (src/pl-list.jl: the comparison cannot fail), so that test is unwritten.
"`profiler(-Old, +New)`: unify Old with the state of the profiler and set it to New (pl-prof.c)."
function pl_profiler2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    PL_unify_atom(ld, A1, prof_status_atom(T, ld.profile.active)) || return FFALSE
    rc = PL_compare(ld, A1, A2)
    rc == CMP_EQUAL && return FTRUE
    val = get_prof_status(ld, A2)
    val === nothing && return FFALSE
    val == ld.profile.active && return FTRUE

    if val != PROF_INACTIVE
        return startProfiler(ld, val) ? FTRUE : FFALSE
    else
        return stopProfiler(ld) ? FTRUE : FFALSE
    end
end

# PORT: pl-prof.c profile as pl_profile4_va
# (PRED_IMPL("$profile", 4, profile, PL_FA_TRANSPARENT))
# DIVERGES: refused by name at `startProfiler`, after the options are set and the data reset (as upstream's order); `rate` out of
# `unsigned int` (zero, infinite, negative: undefined in C) gives period 0. Without the refusal `callProlog` (context 0) would follow.
"`'\$profile'(:Goal, +Status, +Ports, +Rate)`: run Goal under the profiler (pl-prof.c)."
function pl_profile4_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3, A4 = PL__t0, PL__t0 + 1, PL__t0 + 2, PL__t0 + 3
    val = get_prof_status(ld, A2)
    val === nothing && return FFALSE

    ports_opt = PL_get_atom_ex(ld, A3)
    ports_opt === nothing && return FFALSE
    pk = sym_key(ports_opt)
    ld.profile.ports_control =
        if pk == sym_key(mk_sym(T, Symbol("false")))
            PROFC_FALSE
        elseif pk == sym_key(mk_sym(T, Symbol("true")))
            PROFC_TRUE
        else
            PROFC_CLASSIC
        end

    ld.profile.sample_period = DEFAULT_SAMPLE_PERIOD
    rate = PL_get_float_ex(ld, A4)
    rate === nothing && return FFALSE
    x = 1000000 / rate::Float64
    ld.profile.sample_period =
        (isfinite(x) && x >= 0 && x < 4294967296.0) ? Int(trunc(x)) : 0

    resetProfiler(ld)
    startProfiler(ld, val) || return FFALSE
    rc = callProlog(_query_gd(ld), ld, 0, A1, PL_Q_PASS_EXCEPTION)
    stopProfiler(ld)

    return rc ? FTRUE : FFALSE
end

const PROF_EXACT_MAX_CLOCK_NS = 40.0    # auto: max cost of prof_clock()

# PORT: pl-prof.c prof_clock_cost_ns
# DIVERGES: refused by name: the cost is MEASURED, 3 runs of 1000 `prof_clock()` reads timed with `prof_mono_ns()` (pl-prof.c:349-373).
"The cost of one `prof_clock()` in nsec, refused by name: there is no clock to time (PROF1)."
function prof_clock_cost_ns(ld::PL_local_data{T})::Float64 where {T}
    _prof_refuse(
        ld,
        :prof_clock_cost_ns,
        "the cost of reading the exact clock (`prof_clock()`: the TSC or the monotonic clock)"
    )
end

# PORT: pl-prof.c precise_thread_cpu_clock
# DIVERGES: refused by name: it probes `prof_thread_cpu_ns()` for 2 changes within 3 ms (pl-prof.c:295-345); the result is (ok, why).
"Is the thread CPU clock precise? Refused by name: there is no thread CPU clock to probe (PROF1)."
function precise_thread_cpu_clock(ld::PL_local_data{T})::Tuple{Bool, String} where {T}
    _prof_refuse(
        ld,
        :precise_thread_cpu_clock,
        "probing the thread CPU clock (`prof_thread_cpu_ns()`, 2 changes within 3 ms)"
    )
end

# PORT: pl-prof.c prof_exact_ok as pl_prof_exact_ok1_va
# (PRED_IMPL("$prof_exact_ok", 1, prof_exact_ok, 0))
"`'\$prof_exact_ok'(+Clock)`: the atom check, then the clock's cost, then (for `cpu`) the CPU clock's precision: both named refusals (pl-prof.c:903)."
function pl_prof_exact_ok1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    clock = PL_get_atom_ex(ld, PL__t0)
    clock === nothing && return FFALSE
    prof_clock_cost_ns(ld) > PROF_EXACT_MAX_CLOCK_NS && return FFALSE
    if sym_key(clock) == sym_key(mk_sym(T, :cpu))
        return precise_thread_cpu_clock(ld)[1] ? FTRUE : FFALSE
    end
    return FTRUE
end

# PORT: pl-prof.c prof_clock_cost as pl_prof_clock_cost1_va
# (PRED_IMPL("$prof_clock_cost", 1, prof_clock_cost, 0))
"`'\$prof_clock_cost'(-Nsec)`: the clock's cost, a named refusal (pl-prof.c:924)."
function pl_prof_clock_cost1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return PL_unify_float(ld, PL__t0, prof_clock_cost_ns(ld)) ? FTRUE : FFALSE
end

# ── SECOND HALF of pl-prof.c: the dynamic call tree's builders (the VM's call, exit and fail ports) and the charge functions ──────
#
# `profCall`, `profResumeParent`, `profExit`, `profFail` and `prof_call` are the data part: they build the tree and count calls,
# exits, fails and recursion, as upstream. They have NO CALLER in this kernel (its VM has no profiling hooks); a test drives them.
# The charge functions read a clock (`prof_clock`, `prof_mono_ns`, `prof_thread_cpu_ns`, `prof_clock_per_ns`, pl-prof.c:57-153, 274-400):
# those four are named refusals (PROF1), the arithmetic around them is ported as written, so an exact mode (reachable only by a test
# setting `ld.profile.active`) runs up to the clock and refuses there.

# DIVERGES: upstream's `prof_clock()` reads the TSC or the OS monotonic clock (pl-prof.c:57-153): named refusal.
"The exact clock's reading, refused by name (pl-prof.c `prof_clock`)."
function prof_clock(ld::PL_local_data{T})::Int where {T}
    _prof_refuse(
        ld, :prof_clock, "reading the exact clock (the TSC or the monotonic clock)"
    )
end

# DIVERGES: upstream's `prof_mono_ns()` is the OS monotonic clock in nsec: named refusal.
"The monotonic time in nsec, refused by name (pl-prof.c `prof_mono_ns`)."
function prof_mono_ns(ld::PL_local_data{T})::Int where {T}
    _prof_refuse(ld, :prof_mono_ns, "reading the OS monotonic clock")
end

# DIVERGES: upstream's `prof_thread_cpu_ns()` is the thread's CPU time (pl-prof.c:278): named refusal.
"The thread's CPU time in nsec, refused by name (pl-prof.c `prof_thread_cpu_ns`)."
function prof_thread_cpu_ns(ld::PL_local_data{T})::Int where {T}
    _prof_refuse(ld, :prof_thread_cpu_ns, "reading the thread CPU clock")
end

# DIVERGES: upstream's `prof_clock_per_ns()` calibrates `prof_clock()` units against nsec (pl-prof.c:379): named refusal.
"The `prof_clock()` units per nsec, refused by name (pl-prof.c `prof_clock_per_ns`)."
function prof_clock_per_ns(ld::PL_local_data{T})::Float64 where {T}
    _prof_refuse(ld, :prof_clock_per_ns, "calibrating the exact clock")
end

# DIVERGES: upstream's `thread_prof_ticks()` reads the profiled thread's CPU or wall clock (pl-prof.c:632): named refusal.
"The ticks since the last tick, refused by name (pl-prof.c `thread_prof_ticks`)."
function thread_prof_ticks(ld::PL_local_data{T})::Int where {T}
    _prof_refuse(ld, :thread_prof_ticks, "reading the profiled thread's clock")
end

# ORIGINAL: C's `llround` (half away from zero) on a double.
_llround(x::Float64)::Int = round(Int, x, RoundNearestTiesAway)

# PORT: pl-prof.c prof_close_window
# DIVERGES: `lnode` is the node or `nothing` (a NULL pointer); the window's node chain holds node indexes.
"Close the CPU-exact accounting window: charge the CPU time to the nodes that ran in it (pl-prof.c)."
function prof_close_window(
    ld::PL_local_data{T}, now::Int, lnode::Union{Nothing, call_node{T}}, ldelta::Int
)::Nothing where {T}
    p = ld.profile
    cpu = prof_thread_cpu_ns(ld)
    dcpu = cpu - p.clock.win_cpu
    raw = now - p.clock.win_start - ldelta
    scale = 0.0                                         # nsec per prof_clock() unit

    dcpu < 0 && (dcpu = 0)
    if lnode !== nothing
        per_ns = prof_clock_per_ns(ld)
        short_ns = Float64(raw) / per_ns

        if Float64(dcpu) >= short_ns
            long_ns = Float64(dcpu) - short_ns
            max_ns = Float64(ldelta) / per_ns

            long_ns > max_ns && (long_ns = max_ns)
            lnode.ticks += _llround(long_ns)
            scale = 1.0 / per_ns
        else                                            # short intervals were preempted
            scale = Float64(dcpu) / Float64(raw)
        end
    else
        scale = raw != 0 ? Float64(dcpu) / Float64(raw) : 0.0
    end

    n = p.clock.win_nodes
    while n != 0
        nn = prof_node_at(ld, n)::call_node{T}
        nxt = nn.win_next
        nn.ticks += _llround(Float64(nn.raw) * scale)
        nn.raw = 0
        nn.win_next = 0
        nn.in_window = false
        n = nxt
    end
    p.accounting_ticks += _llround(Float64(p.clock.win_accounting) * scale)
    p.ticks += dcpu

    p.clock.win_nodes = 0
    p.clock.win_accounting = 0
    p.clock.win_start = now
    p.clock.win_cpu = cpu
    return nothing
end

# PORT: pl-prof.c prof_charge
# DIVERGES: `node` is a node pointer (an index; 0 = NULL, as upstream's `node && node->magic != PROFNODE_MAGIC` -> NULL).
"Charge the time since the last clock reading to the node at `ptr` or, if `accounting`, to the profiler's accounting (pl-prof.c)."
function prof_charge(ld::PL_local_data{T}, ptr::Int, accounting::Bool)::Nothing where {T}
    p = ld.profile
    now = prof_clock(ld)
    delta = now - p.clock.last

    delta < 0 && (delta = 0)                            # unsynchronised counters?
    p.clock.last = now
    node = prof_node_at(ld, ptr)                        # nothing when 0 or not a live node

    if p.active == PROF_CPU_EXACT
        if delta >= p.clock.long_interval && node !== nothing && !accounting
            prof_close_window(ld, now, node, delta)
            return nothing
        end
        if accounting
            p.clock.win_accounting += delta
        elseif node !== nothing
            if !node.in_window
                node.in_window = true
                node.win_next = p.clock.win_nodes
                p.clock.win_nodes = ptr
            end
            node.raw += delta
        end
        if now - p.clock.win_start >= p.clock.win_length
            prof_close_window(ld, now, nothing, 0)
        end
    else
        p.clock.raw += delta
        if accounting
            p.clock.accounting += delta
        elseif node !== nothing
            node.raw += delta
        end
    end
    return nothing
end

# Global stack accounting (pl-prof.c). Like the exact time modes, we read a clock each time the current node of the call tree changes
# and charge the difference to the node we leave. The clock is the global stack in use plus what GC has reclaimed, such that GC does
# not make it go back. It does go back if backtracking discards global stack. On backtracking we read the clock before the stacks
# are reset (`profBacktrack`), charging what was allocated to the current node, and after (`profFail`), charging what was discarded
# to the node that created the choicepoint. E.g., for `p :- \+ \+ q`, q allocated X and p discarded X. Other events that make the
# clock go back, such as exceptions, charge the discarded memory to the current node.

# ORIGINAL: `LD->gc.stats.totals.global_gained`, `LD->gc.stats.totals.collections`: this kernel has no stack garbage collector
# (file-wide 6), the totals are 0.
"The global stack gained by GC in total (pl-gc.c `LD->gc.stats.totals.global_gained`): 0, no collector runs."
prof_gc_global_gained(ld::PL_local_data)::Int = 0
"The number of garbage collections in total (`LD->gc.stats.totals.collections`): 0, no collector runs."
prof_gc_collections(ld::PL_local_data)::Int = 0

# PORT: pl-prof.c prof_mem_clock
"The global stack in use plus what GC has reclaimed (pl-prof.c)."
prof_mem_clock(ld::PL_local_data)::Int =
    _used_stack(ld, :global) + prof_gc_global_gained(ld)

# PORT: pl-prof.c prof_mem_charge
# DIVERGES: the nodes are node pointers (0 = NULL; `prof_node_at` is upstream's `magic == PROFNODE_MAGIC` check).
"Charge the change of the memory clock: an increase to `alloc_node`, a decrease to `discard_node` (pl-prof.c)."
function prof_mem_charge(
    ld::PL_local_data{T}, alloc_node::Int, discard_node::Int
)::Nothing where {T}
    now = prof_mem_clock(ld)
    last = ld.profile.mem.last

    ld.profile.mem.last = now
    if now > last
        delta = now - last

        ld.profile.mem.allocated += delta
        an = prof_node_at(ld, alloc_node)
        an !== nothing && (an.mem.allocated += delta)
    elseif now < last
        delta = last - now

        ld.profile.mem.discarded += delta
        dn = prof_node_at(ld, discard_node)
        dn !== nothing && (dn.mem.discarded += delta)
    end
    return nothing
end

# PORT: pl-prof.c prof_accounting_begin
"Start counting the profiler's own work (pl-prof.c)."
function prof_accounting_begin(ld::PL_local_data{T})::Nothing where {T}
    if PROF_IS_EXACT(ld.profile.active)
        ld.profile.samples += 1
        prof_charge(ld, ld.profile.current, false)
    end
    prof_mem_charge(ld, ld.profile.current, ld.profile.current)
    ld.profile.accounting = true
    return nothing
end

# PORT: pl-prof.c prof_accounting_end
"Stop counting the profiler's own work (pl-prof.c)."
function prof_accounting_end(ld::PL_local_data{T})::Nothing where {T}
    if PROF_IS_EXACT(ld.profile.active)
        prof_charge(ld, 0, true)
    end
    ld.profile.accounting = false
    return nothing
end

# PORT: pl-prof.c prof_convert_clock
"Convert the `prof_clock()` counts collected since activation to nsec (pl-prof.c); refused at the monotonic clock."
function prof_convert_clock(ld::PL_local_data{T})::Nothing where {T}
    p = ld.profile
    ns = prof_mono_ns(ld) - p.clock.start_ns
    raw = p.clock.last - p.clock.start
    scale = raw != 0 ? Float64(ns) / Float64(raw) : 0.0
    n = p.roots

    while n != 0                                        # depth-first walk of the tree
        nn = prof_node_at(ld, n)::call_node{T}
        nn.ticks += _llround(Float64(nn.raw) * scale)
        nn.raw = 0
        if nn.siblings != 0
            n = nn.siblings
        else
            while n != 0 && (prof_node_at(ld, n)::call_node{T}).next == 0
                n = (prof_node_at(ld, n)::call_node{T}).parent
            end
            if n != 0
                n = (prof_node_at(ld, n)::call_node{T}).next
            end
        end
    end

    p.ticks += _llround(Float64(p.clock.raw) * scale)
    p.accounting_ticks += _llround(Float64(p.clock.accounting) * scale)
    p.clock.raw = 0
    p.clock.accounting = 0
    return nothing
end

# PORT: pl-prof.c prof_call
# DIVERGES: file-wide 1 and 5 (`handle` is a `Definition` or `nothing`; the node pointer is an index; no `allocHeapOrHalt`); returns the pointer.
"A call was made from the current node to `handle`: build the dynamic call tree and return the node's pointer (pl-prof.c)."
function prof_call(
    ld::PL_local_data{T}, handle::Union{Nothing, Definition{T}}, type::Int
)::Int where {T}
    p = ld.profile
    node = p.current

    prof_accounting_begin(ld)

    if node == 0                                        # root-node of the profile
        n = p.roots
        while n != 0
            nn = prof_node_at(ld, n)::call_node{T}
            if nn.handle === handle
                nn.calls += 1
                p.current = n
                prof_accounting_end(ld)
                return n
            end
            n = nn.next
        end

        ptr = new_call_node!(ld, handle, type)
        nn = prof_node_at(ld, ptr)::call_node{T}
        nn.calls += 1
        nn.next = p.roots
        p.roots = ptr
        p.current = ptr
        prof_accounting_end(ld)
        return ptr
    end

    cur = prof_node_at(ld, node)::call_node{T}
    if cur.handle === handle                            # straight recursion
        cur.recur += 1
        prof_accounting_end(ld)
        return node
    elseif p.ports_control != PROFC_TRUE
        parent = cur.handle

        n = cur.parent
        while n != 0
            nn = prof_node_at(ld, n)::call_node{T}
            if nn.handle === handle && nn.parent != 0 &&
                (prof_node_at(ld, nn.parent)::call_node{T}).handle === parent
                nn.recur += 1
                p.current = n
                prof_accounting_end(ld)
                return n
            end
            n = nn.parent
        end
    end

    s = cur.siblings
    while s != 0
        sn = prof_node_at(ld, s)::call_node{T}
        if sn.handle === handle
            p.current = s
            sn.calls += 1
            prof_accounting_end(ld)
            return s
        end
        s = sn.next
    end

    ptr = new_call_node!(ld, handle, type)
    nn = prof_node_at(ld, ptr)::call_node{T}
    nn.parent = p.current
    nn.calls += 1
    nn.next = cur.siblings
    cur.siblings = ptr
    p.current = ptr
    prof_accounting_end(ld)
    return ptr
end

# PORT: pl-prof.c profCall
# DIVERGES: file-wide 5 (`acquireModulePtr`: no module reference count).
"A call to `def`: the node's pointer (the current node's, for a predicate not profiled; pl-prof.c)."
function profCall(ld::PL_local_data{T}, def::Definition{T})::Int where {T}
    (def.flags & P_NOPROFILE) != 0 && return ld.profile.current
    return prof_call(ld, def, PROF_TYPE_DEFAULT)
end

# PORT: pl-prof.c profResumeParent
"Exit, resuming execution in the node at `node` (a stale pointer is ignored; pl-prof.c)."
function profResumeParent(ld::PL_local_data{T}, node::Int)::Nothing where {T}
    if node != 0 && prof_node_at(ld, node) === nothing  # node && node->magic != PROFNODE_MAGIC
        return nothing
    end

    prof_accounting_begin(ld)

    if ld.profile.ports_control != PROFC_FALSE
        n = ld.profile.current
        while n != 0 && n != node
            nn = prof_node_at(ld, n)::call_node{T}
            nn.exits += 1
            n = nn.parent
        end
    end
    ld.profile.current = node

    prof_accounting_end(ld)
    return nothing
end

# PORT: pl-prof.c profExit
"Exit to the parent of `node`: every node from the current one back to `node` has exited (pl-prof.c)."
function profExit(ld::PL_local_data{T}, node::Int)::Nothing where {T}
    nn = prof_node_at(ld, node)
    nn === nothing && return nothing
    profResumeParent(ld, nn.parent)
    return nothing
end

# PORT: pl-prof.c lookback
"Is `to_node` on the parent chain of `from_node`? (pl-prof.c)"
function lookback(ld::PL_local_data{T}, from_node::Int, to_node::Int)::Bool where {T}
    node = from_node
    while node != 0
        node == to_node && return true
        node = (prof_node_at(ld, node)::call_node{T}).parent
    end
    return false
end

# PORT: pl-prof.c profFailToCP
# DIVERGES: a node that is no live node ends the walk (upstream reads its `parent` from freed memory).
"Fail every node from `current` back to a common ancestor with `cp_node` (pl-prof.c)."
function profFailToCP(ld::PL_local_data{T}, current::Int, cp_node::Int)::Nothing where {T}
    while current != 0 && !lookback(ld, cp_node, current)
        n = prof_node_at(ld, current)
        n === nothing && break
        n.fails += 1
        current = n.parent
    end
    return nothing
end

# PORT: pl-prof.c profBacktrack
# Called on backtracking before the stacks are reset (see profFail()). The call is upstream's VM (pl-vmi.c, before `Undo()`).
"Charge the global stack allocated since the last switch to the current node, on backtracking before the stacks are reset (pl-prof.c)."
function profBacktrack(ld::PL_local_data{T})::Nothing where {T}
    prof_mem_charge(ld, ld.profile.current, 0)
    return nothing
end

# PORT: pl-prof.c profFail
"Fail to the choicepoint's node: the nodes of the branch from the current one back to the common ancestor have failed (pl-prof.c)."
function profFail(ld::PL_local_data{T}, cp_node::Int)::Nothing where {T}
    prof_mem_charge(ld, ld.profile.current, cp_node)
    prof_accounting_begin(ld)

    if ld.profile.ports_control != PROFC_FALSE
        profFailToCP(ld, ld.profile.current, cp_node)
    end
    ld.profile.current = cp_node

    prof_accounting_end(ld)
    return nothing
end

# PORT: pl-prof.c profSetHandle
"Set the handle of a node (pl-prof.c)."
function profSetHandle(
    node::call_node{T}, handle::Union{Nothing, Definition{T}}
)::Nothing where {T}
    node.handle = handle
    return nothing
end

# PORT: pl-prof.c PL_register_profile_type
# DIVERGES: refused by name: a foreign profile type is a table of C function pointers (identify, get, acquire, release); the type table
# of this kernel holds the default type only (file-wide 1).
"Register a foreign profile type: refused by name (PROF1; pl-prof.c:1847)."
function PL_register_profile_type(ld::PL_local_data{T}, name::String)::Bool where {T}
    _prof_refuse(
        ld, :PL_register_profile_type, "a foreign profile type (C function pointers)"
    )
end

# PORT: pl-prof.c PL_prof_call
"The foreign call into the profile tree: refused by name (PROF1; pl-prof.c:1868): its handle is a C pointer."
function PL_prof_call(ld::PL_local_data{T}, handle::Int, type::Int)::Int where {T}
    _prof_refuse(
        ld, :PL_prof_call, "a foreign profile handle (a C `void *` of a foreign type)"
    )
end

# PORT: pl-prof.c PL_prof_exit
"The foreign exit from the profile tree: refused by name (PROF1; pl-prof.c:1875)."
function PL_prof_exit(ld::PL_local_data{T}, node::Int)::Nothing where {T}
    _prof_refuse(ld, :PL_prof_exit, "a foreign profile node (a C `void *`)")
end

# PORT: pl-prof.c BeginPredDefs as PL_predicates_from_profile
"pl-prof.c's registration table (`BeginPredDefs(profile)`, under `O_PROFILE`; the pin's swipl has it)."
const PL_predicates_from_profile = (
    PL_extension("\$profile", 4, pl_profile4_va, PL_FA_TRANSPARENT | PL_FA_VARARGS),
    PL_extension("profiler", 2, pl_profiler2_va, PL_FA_VARARGS),
    PL_extension("\$prof_exact_ok", 1, pl_prof_exact_ok1_va, PL_FA_VARARGS),
    PL_extension("\$prof_clock_cost", 1, pl_prof_clock_cost1_va, PL_FA_VARARGS),
    PL_extension("reset_profiler", 0, pl_reset_profiler0_va, PL_FA_VARARGS),
    PL_extension("\$prof_node", 8, pl_prof_node8_va, PL_FA_VARARGS),
    PL_extension(
        "\$prof_sibling_of",
        2,
        pl_prof_sibling_of2_va,
        PL_FA_NONDETERMINISTIC | PL_FA_VARARGS
    ),
    PL_extension(
        "\$prof_procedure_data",
        9,
        pl_prof_procedure_data9_va,
        PL_FA_TRANSPARENT | PL_FA_VARARGS
    ),
    PL_extension("\$prof_procedures", 1, pl_prof_procedures1_va, PL_FA_VARARGS),
    PL_extension("\$prof_statistics", 9, pl_prof_statistics9_va, PL_FA_VARARGS)
)
