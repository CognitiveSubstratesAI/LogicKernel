# UPSTREAM: swipl-devel src/pl-prof.c @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-prof.h @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2025, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# allow-new-artifact: a port of the pin's src/pl-prof.c, read from the pin (git show 18168e62) for this file
#
# PROF1 (pl-prof.c), lane F, FIRST HALF: the data layer of the profiler: the call tree (`call_node`, src/pl-incl.jl), the status
# atoms, the node pointer, and the foreign predicates that read it ('$prof_sibling_of'/2, '$prof_node'/8,
# '$prof_procedure_data'/8, '$prof_statistics'/8) or reset it (reset_profiler/0), with `profiler/2` and `'$profile'/4`.
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
#   4. `get_def`: `get_procedure(..., GP_FIND|GP_NAMEARITY|GP_TYPE_QUIET)` is `get_procedure_namearity` (src/pl-proc.jl), whose
#      type errors are not quiet: a term that is no indicator fails here after its error is cleared.
#   5. MEMORY: no `allocHeap`, no `releaseModule` (`prof_release_def`: no module GC), the `prof_ref` chains are vectors
#      (new references are pushed at the end and unified from the end, upstream's order of `r->next = callers; callers = r`).

# ORIGINAL: the refusal every collection entry point raises (step PROF1).
function _prof_refuse(ld::PL_local_data{T}, culprit::Symbol, what::String)::Union{} where {T}
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
function prof_node_at(ld::PL_local_data{T}, ptr::Int)::Union{Nothing, call_node{T}} where {T}
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
    s = sym_name(a)
    s === :false && return PROF_INACTIVE
    (s === :true || s === :cputime) && return PROF_CPU
    s === :walltime && return PROF_WALL
    s === :exact_walltime && return PROF_WALL_EXACT
    s === :exact_cputime && return PROF_CPU_EXACT
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
    return mk_sym(T, :false)
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
    PL_error(ld, ERR_TYPE, mk_sym(T, :profile_node), t)
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
            if a !== nothing && sym_name(a) === :(-)
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
    return unify_definition(gd, ld, MODULE_user(gd), t, handle, 0, GP_QUALIFY | GP_NAMEARITY)
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
    return (
        unify_node_id(gd, ld, PL__t0 + 1, n) &&
        PL_unify_int64(ld, PL__t0 + 2, n.calls) &&
        PL_unify_int64(ld, PL__t0 + 3, n.exits + n.fails - n.calls) &&
        PL_unify_int64(ld, PL__t0 + 4, n.exits) &&
        PL_unify_int64(ld, PL__t0 + 5, n.recur) &&
        PL_unify_int64(ld, PL__t0 + 6, n.ticks) &&
        PL_unify_int64(ld, PL__t0 + 7, n.sibling_ticks)
    ) ? FTRUE : FFALSE
end

# PORT: pl-prof.h DEF_SPONTANEOUS / DEF_RECURSIVE (pl-prof.c: `(Definition)0` and `(Definition)1`)
# DIVERGES: the two special handles are the kinds of a reference, its `handle` being `nothing` then.
const PROF_REF_DEF = 0
const PROF_REF_SPONTANEOUS = 1
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
    calls::Int                                  # calls to/from this predicate
    redos::Int                                  # redos to/from this predicate
    exits::Int                                  # exits to/from this predicate
end

# PORT: pl-prof.c node_sum
"The summary of one procedure over the call tree (pl-prof.c `node_sum`)."
mutable struct node_sum{T}
    ticks::Int
    sibling_ticks::Int
    calls::Int
    redos::Int
    exits::Int
    recur::Int
    callers::Vector{prof_ref{T}}
    callees::Vector{prof_ref{T}}
end
node_sum{T}() where {T} = node_sum{T}(0, 0, 0, 0, 0, 0, prof_ref{T}[], prof_ref{T}[])

# PORT: pl-prof.c node_redos
"The redos of a node: its exits and fails beyond its calls (a call still running counts none; pl-prof.c)."
function node_redos(n::call_node{T})::Int where {T}
    left = n.exits + n.fails
    return left > n.calls ? left - n.calls : 0
end

# PORT: pl-prof.c add_parent_ref
"Add the node `self` to the callers of `sum`: `handle` (`kind`) its parent (pl-prof.c)."
function add_parent_ref!(
    sum::node_sum{T}, self::call_node{T}, kind::Int, handle::Union{Nothing, Definition{T}}, type::Int, cycle::Int
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
            return nothing
        end
    end

    push!(
        sum.callers,
        prof_ref{T}(kind, handle, type, cycle, self.ticks, self.sibling_ticks, self.calls, node_redos(self), self.exits)
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
    push!(sum.callers, prof_ref{T}(PROF_REF_RECURSIVE, nothing, 0, cycle, 0, 0, count, 0, 0))
    return nothing
end

# PORT: pl-prof.c add_sibling_ref
"Add the node `sibling` to the callees of `sum` (pl-prof.c)."
function add_sibling_ref!(sum::node_sum{T}, sibling::call_node{T}, cycle::Int)::Nothing where {T}
    for r in sum.callees
        if r.kind == PROF_REF_DEF && r.handle === sibling.handle && r.cycle == cycle
            r.calls += sibling.calls
            r.redos += node_redos(sibling)
            r.exits += sibling.exits
            r.ticks += sibling.ticks
            r.sibling_ticks += sibling.sibling_ticks
            return nothing
        end
    end
    push!(
        sum.callees,
        prof_ref{T}(
            PROF_REF_DEF, sibling.handle, sibling.type, cycle, sibling.ticks, sibling.sibling_ticks,
            sibling.calls, node_redos(sibling), sibling.exits
        )
    )
    return nothing
end

# PORT: pl-prof.c sumProfile
# DIVERGES: file-wide 2 (`PL_handle_signals`, which can only fail on an aborted run, has no twin).
"Sum the procedure `handle` over the subtree of the node `n`: the number of nodes of it (pl-prof.c)."
function sumProfile(
    ld::PL_local_data{T}, n::call_node{T}, handle::Definition{T}, sum::node_sum{T}, seen::Int
)::Int where {T}
    count = 0

    if n.handle === handle
        count += 1
        sum.ticks += n.ticks
        if seen == 0
            sum.sibling_ticks += n.sibling_ticks
        else                                            # nested: n's ticks are in the outer siblings
            sum.sibling_ticks -= n.ticks
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

        seen += 1
    end

    s = n.siblings
    while s != 0
        sn = prof_node_at(ld, s)::call_node{T}
        count += sumProfile(ld, sn, handle, sum, seen)
        s = sn.next
    end

    return count
end

# PORT: pl-prof.c unify_relatives
"Unify the list `list` with the `node/7` terms of the references `refs` (pl-prof.c)."
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
        PL_unify_functor(ld, head, mk_sym(T, :node), 7) || return false
        a = PL_new_term_ref(ld)
        vals = (nothing, r.cycle, r.ticks, r.sibling_ticks, r.calls, r.redos, r.exits)
        for i in 1:7
            _PL_get_arg(ld, i, head, a)
            ok = i == 1 ? PL_unify(ld, a, tmp) : PL_unify_int64(ld, a, vals[i]::Int)
            ok || return false
        end
    end

    return PL_unify_nil(ld, tail)
end

# PORT: pl-prof.c get_def
# DIVERGES: file-wide 4.
"The definition the `Name/Arity` in `t` names, or `nothing` (a failure; pl-prof.c)."
function get_def(
    gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t
)::Union{Nothing, Definition{T}} where {T}
    proc = get_procedure_namearity(gd, ld, t, MODULE_user(gd), GP_FIND | GP_NAMEARITY)
    if proc === nothing
        PL_clear_exception(ld)                          # GP_TYPE_QUIET
        return nothing
    end
    return proc.definition
end

# PORT: pl-prof.c get_handle
# DIVERGES: file-wide 1: the type table holds the default type only.
"The profile handle `t` names, offered to every registered type in turn (pl-prof.c)."
get_handle(gd::PL_global_data{T}, ld::PL_local_data{T}, t::term_t) where {T} = get_def(gd, ld, t)

# PORT: pl-prof.c prof_procedure_data as pl_prof_procedure_data8_va
# (PRED_IMPL("$prof_procedure_data", 8, prof_procedure_data, PL_FA_TRANSPARENT))
# DIVERGES: the context module of the transparent predicate is `user` (as compile_predicates/1: the caller's context is left out).
"`'\$prof_procedure_data'(+PI, -Ticks, -TicksSiblings, -Calls, -Redos, -Exits, -Callers, -Callees)` (pl-prof.c)."
function pl_prof_procedure_data8_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    handle = get_handle(gd, ld, PL__t0)
    handle === nothing && return FFALSE
    collectSiblingsTime(ld)
    sum = node_sum{T}()
    count = 0
    n = ld.profile.roots
    while n != 0
        nn = prof_node_at(ld, n)::call_node{T}
        count += sumProfile(ld, nn, handle, sum, 0)
        n = nn.next
    end

    count == 0 && return FFALSE                         # nothing known about this one

    return (
        PL_unify_int64(ld, PL__t0 + 1, sum.ticks) &&
        PL_unify_int64(ld, PL__t0 + 2, sum.sibling_ticks) &&
        PL_unify_int64(ld, PL__t0 + 3, sum.calls) &&
        PL_unify_int64(ld, PL__t0 + 4, sum.redos) &&
        PL_unify_int64(ld, PL__t0 + 5, sum.exits) &&
        unify_relatives(gd, ld, PL__t0 + 6, sum.callers) &&
        unify_relatives(gd, ld, PL__t0 + 7, sum.callees)
    ) ? FTRUE : FFALSE
end

# PORT: pl-prof.c prof_statistics as pl_prof_statistics8_va
# (PRED_IMPL("$prof_statistics", 8, prof_statistics, 0))
"`'\$prof_statistics'(-Samples, -Ticks, -AccountingTicks, -Time, -Nodes, -Period, -Ports, -Mode)` (pl-prof.c)."
function pl_prof_statistics8_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    p = ld.profile
    ports = p.ports_control == PROFC_FALSE ? :false : p.ports_control == PROFC_TRUE ? :true : :classic
    return (
        PL_unify_int64(ld, PL__t0, p.samples) &&
        PL_unify_int64(ld, PL__t0 + 1, p.ticks) &&
        PL_unify_int64(ld, PL__t0 + 2, p.accounting_ticks) &&
        PL_unify_float(ld, PL__t0 + 3, p.time) &&
        PL_unify_int64(ld, PL__t0 + 4, p.nodes) &&
        PL_unify_integer(ld, PL__t0 + 5, p.sample_period) &&
        PL_unify_atom(ld, PL__t0 + 6, mk_sym(T, ports)) &&
        PL_unify_atom(ld, PL__t0 + 7, prof_status_atom(T, p.mode))
    ) ? FTRUE : FFALSE
end

# PORT: pl-prof.c collectSiblingsNode
"The ticks of the subtree of `n`, setting each node's `sibling_ticks` (pl-prof.c)."
function collectSiblingsNode(ld::PL_local_data{T}, n::call_node{T})::Int where {T}
    count = 0
    s = n.siblings
    while s != 0
        sn = prof_node_at(ld, s)::call_node{T}
        count += collectSiblingsNode(ld, sn)
        n.sibling_ticks = count
        s = sn.next
    end
    return count + n.ticks
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
# DIVERGES: file-wide 2: `GD->profile.thread` has no field and the profiler cannot be started, so an active profiler (reachable
# only by a test that sets `ld.profile.active`) is a named refusal at the clock it would read.
"Stop the profiler: true when it is not running (pl-prof.c)."
function stopProfiler(ld::PL_local_data{T})::Bool where {T}
    if ld.profile.active != PROF_INACTIVE
        _prof_refuse(ld, :stopProfiler, "stopping a running profiler (`ThreadCPUTime`, `prof_charge`, `setitimer`: the profiler cannot be started)")
    end
    return true
end

# PORT: pl-prof.c activateProfiler
"Mark the profiler active: refused by name, the profiler's clocks and signals have no equivalent (pl-prof.c:549-630)."
function activateProfiler(ld::PL_local_data{T}, active::Int)::Bool where {T}
    _prof_refuse(ld, :activateProfiler, "activating the profiler (the thread CPU clock, the TSC, `GD->profile.thread`)")
end

# PORT: pl-prof.c startProfiler
# DIVERGES: refused by name after the statement that precedes the exact-mode branch (the sample period default).
"Start the profiler in mode `how`: refused by name, SIGPROF/SIGALRM and `setitimer` have no equivalent (pl-prof.c:759-800)."
function startProfiler(ld::PL_local_data{T}, how::Int)::Bool where {T}
    if !PROF_IS_EXACT(how) && ld.profile.sample_period == 0         # profiler/2 without $profile/4
        ld.profile.sample_period = DEFAULT_SAMPLE_PERIOD
    end
    _prof_refuse(ld, :startProfiler, "starting the profiler (SIGPROF/SIGALRM, `setitimer`, the exact clocks)")
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
    s = sym_name(ports_opt)
    ld.profile.ports_control = s === :false ? PROFC_FALSE : s === :true ? PROFC_TRUE : PROFC_CLASSIC

    ld.profile.sample_period = DEFAULT_SAMPLE_PERIOD
    rate = PL_get_float_ex(ld, A4)
    rate === nothing && return FFALSE
    x = 1000000 / rate::Float64
    ld.profile.sample_period = (isfinite(x) && x >= 0 && x < 4294967296.0) ? Int(trunc(x)) : 0

    resetProfiler(ld)
    startProfiler(ld, val) || return FFALSE
    rc = callProlog(_query_gd(ld), ld, 0, A1, PL_Q_PASS_EXCEPTION)
    stopProfiler(ld)

    return rc ? FTRUE : FFALSE
end

# PORT: pl-prof.c prof_exact_ok as pl_prof_exact_ok1_va
# (PRED_IMPL("$prof_exact_ok", 1, prof_exact_ok, 0))
"`'\$prof_exact_ok'(+Clock)`: the atom check, then refused by name (`prof_clock_cost_ns` reads the TSC; pl-prof.c:349-379)."
function pl_prof_exact_ok1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    clock = PL_get_atom_ex(ld, PL__t0)
    clock === nothing && return FFALSE
    _prof_refuse(ld, Symbol("\$prof_exact_ok"), "the cost of the exact clock (`prof_clock()`: the TSC or the monotonic clock) and the thread CPU clock")
end

# PORT: pl-prof.c prof_clock_cost as pl_prof_clock_cost1_va
# (PRED_IMPL("$prof_clock_cost", 1, prof_clock_cost, 0))
"`'\$prof_clock_cost'(-Nsec)`: refused by name, there is no `prof_clock()` to time (pl-prof.c:349)."
function pl_prof_clock_cost1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    _prof_refuse(ld, Symbol("\$prof_clock_cost"), "the cost of reading the exact clock (`prof_clock()`: the TSC or the monotonic clock)")
end
