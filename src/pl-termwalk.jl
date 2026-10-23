# UPSTREAM: swipl-devel src/pl-termwalk.c @ 8e1bc1110be4
# CLASS: code
# COPYRIGHT: Copyright (c)  2009-2016, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
#
# TERM WALKING — the explicit agendas SWI-Prolog's term primitives walk terms with, instead of
# recursing (a deep term would overflow the C stack; here, Julia's). Upstream is a file of
# variants that a client `#include`s after defining which it wants; ported here:
#   * the plain one (`term_agenda`, compiled when `AC_TERM_WALK` is NOT defined) — the arguments of
#     compounds, which pl-prims.c's `var_occurs_in` walks: on the CELLS (`cell_agenda`, below);
#   * `AC_TERM_WALK` (`ac_term_agenda`), which pl-termhash.c uses — a pre-order walk of every
#     subterm, compound arguments left to right;
#   * `AC_TERM_WALK_LR` (`term_agendaLR`) — the arguments of TWO compounds in step, which
#     pl-prims.c's `do_unify` walks: on the CELLS (`cell_agendaLR`, below).
#
# DIVERGES (`ac_term_agenda`, on terms): a C agenda walks a `Word*` into a compound's argument array;
# here a node is the compound, the child index of its next argument and how many are left (see
# `_comp_shape`). Upstream marks each compound it enters (`set_marked` on its functor cell)
# so that a cyclic term is refused instead of walked forever, and clears the marks as it leaves
# (`ac_clearTermAgenda`). Interface terms are finite trees with no cells to mark: `ac_pushTermAgenda`
# never meets a cycle, and there is nothing to clear. (A cyclic term exists on the cells only, whose
# walks keep upstream's marks.) Nor does `ac_nextTermAgenda`
# dereference a subterm, as upstream's does: it walks resolved terms, which have no bindings
# (`variant_hash_walk`). The segstack is a Vector.

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
# DIVERGES: returns `(found, left, right)` — two POSITIONS — where upstream returns found and
# writes the pair through `lp`/`rp`, so no pair is boxed.
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

# PORT: pl-termwalk.c term_agenda as cell_agenda
# DIVERGES: `work` is a LOCATION (`_deref_loc`'s: a global position, or `-i` for slot `i` — a slot
# only as the one-cell start) and a count, advanced one cell per argument; the segstack a vector,
# reused (L1d step 5). Location 0 is upstream's NULL.
"A one-sided cell agenda (pl-termwalk.c `term_agenda` on locations)."
mutable struct cell_agenda
    loc::Int                            # work.location
    size::Int                           # work.size
    const stack::Vector{NTuple{2, Int}} # stack
end

# PORT: pl-termwalk.c initTermAgenda as initCellAgenda!
# DIVERGES: re-initialises an existing agenda.
"Start agenda `a` at `size` cells from location `loc` (pl-termwalk.c)."
function initCellAgenda!(a::cell_agenda, size::Int, loc::Int)::Nothing
    empty!(a.stack)
    a.loc = loc
    a.size = size
    return nothing
end

# PORT: pl-termwalk.c clearTermAgenda as clearCellAgenda!
"Discard agenda `a`'s pending work (pl-termwalk.c)."
function clearCellAgenda!(a::cell_agenda)::Nothing
    empty!(a.stack)
    a.size = 0
    return nothing
end

# PORT: pl-termwalk.c nextTermAgendaNoDeRef as nextCellAgendaNoDeRef!
"The next location of agenda `a`, not dereferenced; 0 when it is done (pl-termwalk.c)."
@inline function nextCellAgendaNoDeRef!(a::cell_agenda)::Int
    if a.size == 0
        isempty(a.stack) && return 0
        a.loc, a.size = pop!(a.stack)
    end
    a.size -= 1
    l = a.loc
    a.loc = l + 1
    return l
end

# PORT: pl-termwalk.c pushWorkAgenda as pushWorkCellAgenda!
"Walk the `amount` cells from global position `start` next, keeping the current work (pl-termwalk.c)."
@inline function pushWorkCellAgenda!(a::cell_agenda, amount::Int, start::Int)::Nothing
    if amount > 0
        a.size > 0 && push!(a.stack, (a.loc, a.size))
        a.loc = start
        a.size = amount
    end
    return nothing
end
