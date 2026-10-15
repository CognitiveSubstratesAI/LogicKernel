# UPSTREAM: swipl-devel src/pl-termwalk.c @ 8609e216cab9
# CLASS: code
# COPYRIGHT: Copyright (c)  2009-2016, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
#
# TERM WALKING — the explicit agendas SWI-Prolog's term primitives walk terms with, instead of
# recursing (a deep term would overflow the C stack; here, Julia's). Upstream is a file of
# variants that a client `#include`s after defining which it wants; ported here:
#   * the plain one (`term_agenda`, compiled when `AC_TERM_WALK` is NOT defined) — the arguments of
#     compounds, which pl-prims.c's `var_occurs_in` walks;
#   * `AC_TERM_WALK` (`ac_term_agenda`), which pl-termhash.c uses — a pre-order walk of every
#     subterm, compound arguments left to right;
#   * `AC_TERM_WALK_LR` (`term_agendaLR`) — the arguments of TWO compounds in step, which
#     pl-prims.c's `do_unify` walks.
#
# DIVERGES (file-wide): a C agenda walks a `Word*` into a compound's argument array; here a node is
# the compound, the child index of its next argument and how many are left (see `_comp_shape`).
# For `ac_term_agenda`: upstream marks each compound it enters (`set_marked` on its functor cell)
# so that a cyclic term is refused instead of walked forever, and clears the marks as it leaves
# (`ac_clearTermAgenda`). Interface terms are finite trees with no cells to mark: `ac_pushTermAgenda`
# never meets a cycle, and there is nothing to clear. (Cycles made by BINDINGS are the unifier's
# business: pl-prims.c keeps its own visited and link records.) Nor does `ac_nextTermAgenda`
# dereference a subterm, as upstream's does: it walks resolved terms, which have no bindings
# (`variant_hash_walk`). The segstack is a Vector.

# ── the plain agenda (!AC_TERM_WALK) ─────────────────────────────────────────────────────────────
# PORT: pl-termwalk.c aNode
"Arguments still to walk (pl-termwalk.c `aNode`): child `location` of `term` and `size - 1` more."
struct aNode{T}
    term::T             # the compound (unused while `size == 0`)
    location::Int       # child index of the next argument
    size::Int           # arguments still to walk
end

# PORT: pl-termwalk.c term_agenda
"The plain agenda (pl-termwalk.c `term_agenda`)."
mutable struct term_agenda{T}
    work::aNode{T}                  # current work
    stack::Vector{aNode{T}}
end

# PORT: pl-termwalk.c initTermAgenda
# DIVERGES: re-initialises an existing agenda (upstream initialises one on the C stack), so the
# local data can keep one and a walk allocates nothing once its stack has grown.
"Start walking the `size` arguments of compound `t` from child `location` (pl-termwalk.c)."
function initTermAgenda!(
    a::term_agenda{T}, size::Int, t::T, location::Int
)::Nothing where {T}
    empty!(a.stack)
    a.work = aNode{T}(t, location, size)
    return nothing
end

# PORT: pl-termwalk.c clearTermAgenda
"Drop what is left of the walk (pl-termwalk.c)."
function clearTermAgenda!(a::term_agenda)::Nothing
    empty!(a.stack)
    return nothing
end

# PORT: pl-termwalk.c nextTermAgendaNoDeRef
"The next argument, not dereferenced, or `nothing` when the walk is done (pl-termwalk.c)."
function nextTermAgendaNoDeRef!(a::term_agenda{T})::Union{Nothing, T} where {T}
    if a.work.size == 0
        isempty(a.stack) && return nothing
        a.work = pop!(a.stack)
    end
    w = a.work
    a.work = aNode{T}(w.term, w.location + 1, w.size - 1)
    return child(w.term, w.location)
end

# PORT: pl-termwalk.c nextTermAgenda
# DIVERGES: `ld` is the local data upstream reaches implicitly; it is untyped here only because
# `PL_local_data` (src/pl-global.jl) is defined after this file, which defines the agendas it holds.
"The next argument, dereferenced through the bindings in `ld` (pl-termwalk.c)."
function nextTermAgenda!(ld, a::term_agenda{T})::Union{Nothing, T} where {T}
    p = nextTermAgendaNoDeRef!(a)
    p === nothing && return nothing
    return deRef(ld, p)
end

# PORT: pl-termwalk.c pushWorkAgenda
"Walk `amount` arguments of compound `t` from child `location` next (pl-termwalk.c)."
function pushWorkAgenda!(
    a::term_agenda{T}, amount::Int, t::T, location::Int
)::Bool where {T}
    if amount != 0
        if a.work.size > 0
            push!(a.stack, a.work)
        end
        a.work = aNode{T}(t, location, amount)
    end
    return true
end

# ── AC_TERM_WALK ─────────────────────────────────────────────────────────────────────────────────

# PORT: pl-termwalk.c acNode
"A compound whose arguments are being walked (pl-termwalk.c `acNode`)."
struct acNode{T}
    term::T             # the compound; the root term itself in the initial node
    location::Int       # child index of the next argument; 0: the root term itself
    size::Int           # arguments still to walk
end

# PORT: pl-termwalk.c ac_term_agenda
"The walk's agenda (pl-termwalk.c `ac_term_agenda`)."
mutable struct ac_term_agenda{T}
    work::acNode{T}                 # current work
    stack::Vector{acNode{T}}
end

# PORT: pl-termwalk.c ac_initTermAgenda
"An agenda that walks `t` and all its subterms (pl-termwalk.c)."
function ac_initTermAgenda(t)
    T = term_type(t)
    return ac_term_agenda{T}(acNode{T}(t, 0, 1), acNode{T}[])
end

# PORT: pl-termwalk.c ac_nextTermAgenda
"The next subterm in pre-order, or `nothing` when the walk is done (pl-termwalk.c)."
function ac_nextTermAgenda(a::ac_term_agenda{T})::Union{Nothing, T} where {T}
    while a.work.size == 0
        isempty(a.stack) && return nothing
        a.work = pop!(a.stack)
    end
    w = a.work
    a.work = acNode{T}(w.term, w.location + 1, w.size - 1)
    if w.location == 0                  # the initial node: the term itself
        return w.term
    end
    return child(w.term, w.location)
end

# PORT: pl-termwalk.c ac_pushTermAgenda
# DIVERGES: returns the compound's `(offset of argument 0, arity)` (see `_comp_shape`) where
# upstream returns its functor through `fp`; never refuses (no cycles).
"Walk the arguments of compound `t` next; its `(off, arity)` (pl-termwalk.c)."
function ac_pushTermAgenda(a::ac_term_agenda{T}, t::T)::Tuple{Int, Int} where {T}
    off, arity = _comp_shape(t)
    push!(a.stack, a.work)
    a.work = acNode{T}(t, off, arity)
    return (off, arity)
end

# ── AC_TERM_WALK_LR: two terms in step ───────────────────────────────────────────────────────────
# PORT: pl-termwalk.c aNodeLR
"""
Arguments of two compounds still to walk in step (pl-termwalk.c `aNodeLR`): child `location` of
`left` and of `right`, and `size - 1` more. The unifier only pairs compounds of one shape, so one
location serves both.
"""
struct aNodeLR{T}
    left::T             # left term
    right::T            # right term
    location::Int       # child index of the next pair of arguments
    size::Int           # pairs still to walk
end

# PORT: pl-termwalk.c term_agendaLR
"The two-term agenda (pl-termwalk.c `term_agendaLR`)."
mutable struct term_agendaLR{T}
    work::aNodeLR{T}                # current work
    stack::Vector{aNodeLR{T}}
end

# PORT: pl-termwalk.c initTermAgendaLR
# DIVERGES: re-initialises an existing agenda, as `initTermAgenda!` does.
"Start walking `count` argument pairs of `left` and `right` from child `location` (pl-termwalk.c)."
function initTermAgendaLR!(
    a::term_agendaLR{T}, count::Int, left::T, right::T, location::Int
)::Nothing where {T}
    empty!(a.stack)
    a.work = aNodeLR{T}(left, right, location, count)
    return nothing
end

# PORT: pl-termwalk.c clearTermAgendaLR
"Drop what is left of the walk (pl-termwalk.c)."
function clearTermAgendaLR!(a::term_agendaLR)::Nothing
    empty!(a.stack)
    return nothing
end

# PORT: pl-termwalk.c nextTermAgendaLR
# DIVERGES: returns `(found, left, right)` where upstream returns found and writes the pair through
# `lp`/`rp` — so no pair is boxed (a `Union{Nothing, Tuple}` result allocates one per argument;
# AllocCheck found it). When nothing is found, `left`/`right` are meaningless.
"The next pair of arguments, not dereferenced: `(true, l, r)`, or `(false, …)` when done (pl-termwalk.c)."
function nextTermAgendaLR!(a::term_agendaLR{T})::Tuple{Bool, T, T} where {T}
    if a.work.size == 0
        isempty(a.stack) && return (false, a.work.left, a.work.right)
        a.work = pop!(a.stack)
    end
    w = a.work
    a.work = aNodeLR{T}(w.left, w.right, w.location + 1, w.size - 1)
    return (true, child(w.left, w.location), child(w.right, w.location))
end

# PORT: pl-termwalk.c pushWorkAgendaLR
"Walk `amount` argument pairs of `left` and `right` from child `location` next (pl-termwalk.c)."
function pushWorkAgendaLR!(
    a::term_agendaLR{T}, amount::Int, left::T, right::T, location::Int
)::Bool where {T}
    if a.work.size > 0
        push!(a.stack, a.work)
    end
    a.work = aNodeLR{T}(left, right, location, amount)
    return true
end

# ── the LR agenda on CELLS (L1c sub-commit 4: do_unify over the global stack) ─────────────────────
# PORT: pl-termwalk.c term_agendaLR as cell_agendaLR
# DIVERGES: the two terms are global POSITIONS (the functor cell of each compound; an argument pair
# is `left + i`, `right + i`), so the walk reads cells, not terms. Reused by the local data: one
# allocation-free walk after the first.
"The two-term agenda over the argument cells of two compounds (pl-termwalk.c `term_agendaLR`)."
mutable struct cell_agendaLR
    left::Int                       # current work: the left compound's base position
    right::Int                      # … the right one's
    location::Int                   # the next pair's offset from the bases
    size::Int                       # pairs still to walk
    stack::Vector{NTuple{4, Int}}   # the work pushed aside: (left, right, location, size)
end

# PORT: pl-termwalk.c initTermAgendaLR as initCellAgendaLR!
"Start walking `count` argument pairs of the compounds at `left` and `right`, from offset `location` (pl-termwalk.c)."
function initCellAgendaLR!(
    a::cell_agendaLR, count::Int, left::Int, right::Int, location::Int
)::Nothing
    empty!(a.stack)
    a.left = left
    a.right = right
    a.location = location
    a.size = count
    return nothing
end

# PORT: pl-termwalk.c clearTermAgendaLR as clearCellAgendaLR!
"Drop what is left of the walk (pl-termwalk.c)."
function clearCellAgendaLR!(a::cell_agendaLR)::Nothing
    empty!(a.stack)
    a.size = 0
    return nothing
end

# PORT: pl-termwalk.c nextTermAgendaLR as nextCellAgendaLR!
# DIVERGES: returns `(found, left, right)` — two POSITIONS — as `nextTermAgendaLR!` does.
"The next pair of argument cells: `(true, p1, p2)`, or `(false, 0, 0)` when done (pl-termwalk.c)."
function nextCellAgendaLR!(a::cell_agendaLR)::Tuple{Bool, Int, Int}
    if a.size == 0
        isempty(a.stack) && return (false, 0, 0)
        a.left, a.right, a.location, a.size = pop!(a.stack)
    end
    i = a.location
    a.location += 1
    a.size -= 1
    return (true, a.left + i, a.right + i)
end

# PORT: pl-termwalk.c pushWorkAgendaLR as pushWorkCellAgendaLR!
"Walk `amount` argument pairs of the compounds at `left` and `right` from offset `location` next (pl-termwalk.c)."
function pushWorkCellAgendaLR!(
    a::cell_agendaLR, amount::Int, left::Int, right::Int, location::Int
)::Bool
    if a.size > 0
        push!(a.stack, (a.left, a.right, a.location, a.size))
    end
    a.left = left
    a.right = right
    a.location = location
    a.size = amount
    return true
end
