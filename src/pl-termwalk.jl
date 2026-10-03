# UPSTREAM: swipl-devel src/pl-termwalk.c @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  2009-2016, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
#
# TERM WALKING — the explicit agendas SWI-Prolog's term primitives walk terms with, instead of
# recursing (a deep term would overflow the C stack; here, Julia's). Upstream is a file of
# variants that a client `#include`s after defining which it wants; ported here: the
# `AC_TERM_WALK` one (`ac_term_agenda`), which pl-termhash.c uses — a pre-order walk of every
# subterm, compound arguments left to right.
#
# DIVERGES (file-wide): upstream marks each compound it enters (`set_marked` on its functor cell)
# so that a cyclic term is refused instead of walked forever, and clears the marks as it leaves
# (`ac_clearTermAgenda`). Interface terms are finite trees with no cells to mark: `ac_pushTermAgenda`
# never meets a cycle, and there is nothing to clear.

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
ac_initTermAgenda(t::T) where {T} = ac_term_agenda{T}(acNode{T}(t, 0, 1), acNode{T}[])

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
