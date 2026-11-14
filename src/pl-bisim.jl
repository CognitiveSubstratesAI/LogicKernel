# UPSTREAM: swipl-devel src/pl-bisim.c @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-bisim.h @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  2026, SWI-Prolog Solutions b.v.
# allow-new-artifact: a port of the pin's src/pl-bisim.c, read in full from the pin (git show 18168e62) for this file
#
# BISIMULATION (pl-bisim.c), lane F: the smallest graph denoting the same (possibly cyclic) tree as a term —
# term_factorized/3,4, term_minimal/2, term_automaton/2, automaton_minimal/2,3 and '$term_canonical_form'/2. A term
# in the store is a graph; two terms denote the same tree exactly when their graphs are bisimilar. This file
# computes the coarsest bisimulation (Paige-Tarjan style partition refinement), a canonical numbering on it, and
# builds the results on the global stack.
#
# THE CELLS. As upstream the walk gives each physically distinct compound cell a number stored IN THE CELL'S OWN
# FUNCTOR WORD (a tagged integer: meeting an integer there is how sharing and cycles are detected), keeps the
# original words in a buffer (`b`, a Vector of `bs_node`) and puts them back by `restore_graph`. While the numbers
# are in place nothing may allocate on the stacks. A `Word`/`Functor` pointer is a LOCATION (src/pl-prims.jl
# `_deref_loc`: a global position; a functor's arguments are the positions after it).
#
# DIVERGES (file-wide):
#   1. INDEXING. Node ids, class ids, leaf numbers and edge indexes keep upstream's 0-BASED VALUES (an edge holds
#      the node id, or -(leaf+1)); a Julia array is read at `[i + 1]`. `NO_NODE` is -1.
#   2. MEMORY. No `MEMORY_OVERFLOW` (Julia raises its own OutOfMemoryError); `tmp_malloc`/`tmp_free`, the array
#      pool (`bs_pool`, `pool_alloc`, `pool_create`: one block cut into arrays, to keep glibc's mmap threshold out
#      of it) have no twin: every array is a Vector. `GRAPH_OVERFLOW` (a graph that does not fit an `int`) is the
#      local code `BS_GRAPH_OVERFLOW`; the other results are Bool (false: an exception has been raised).
#   3. SORTS. `qsort`/`sort_r` become `sort!` (stable here, where upstream's order among equal keys is whatever
#      qsort leaves): the class numbering within one functor differs, the partition and the canonical result
#      do not (see canonicalise).
#   4. COMPARISON. `compareStandard` raises nothing in this kernel (src/pl-prims.jl), so `leaf_order.failed`
#      is kept for the shape and never set.

"The largest value an edge (upstream's `int`) holds: pl-bisim.c compares sizes with `INT_MAX`."
const BS_INT_MAX = 2147483647
"`alloc_graph`'s result for a graph that does not fit an `int` (pl-incl.h `GRAPH_OVERFLOW`, a local code here)."
const BS_GRAPH_OVERFLOW = -11
"`alloc_graph`'s result for success."
const BS_OK = 1
"No node (pl-bisim.c `NO_NODE`, `(size_t)-1`)."
const NO_NODE = -1
"Every compound argument alike: the key `group_signature` gives them (pl-bisim.c `LEAF_SAME`)."
const LEAF_SAME = 0

# PORT: pl-bisim.c bs_node
"A numbered compound cell (pl-bisim.c `bs_node`): where its functor word is, and the word before numbering."
struct bs_node
    term::Int           # the cell: the position of its functor word
    functor::word       # its functor word before numbering
end

# PORT: pl-bisim.c bs_graph
# DIVERGES: see the file header (indexing; no pool: `pool`, `pool2` have no field, every array is its own Vector;
# `leafp` holds LOCATIONS).
"The graph once the functor words have been put back (pl-bisim.c `bs_graph`): integers only."
Base.@kwdef mutable struct bs_graph
    nodes::Int = 0                  # number of cells
    edges::Int = 0                  # sum of the arities
    leaves::Int = 0                 # distinct non-compound arguments
    leafp::Vector{Int} = Int[]      # [leaves] the location of each leaf
    node::Vector{bs_node} = bs_node[]   # [nodes], owned by the caller
    arg::Vector{Int} = Int[]        # [nodes+1] index into child
    child::Vector{Int} = Int[]      # [edges]: a node id, or -(leaf+1)
    pred::Vector{Int} = Int[]       # [edges] reverse edges
    pred_pos::Vector{Int} = Int[]   # [edges] which argument each came from
    pred_at::Vector{Int} = Int[]    # [nodes+1] index into pred
    arity::Int = 0                  # largest arity in the graph
    class::Vector{Int} = Int[]      # [nodes] class of each node
    order::Vector{Int} = Int[]      # [nodes] node ids grouped by class
    at::Vector{Int} = Int[]         # [nodes] index of a node in order
    class_start::Vector{Int} = Int[]    # [nodes]
    class_len::Vector{Int} = Int[]      # [nodes]
    classes::Int = 0
    vars::Int = 0                   # distinct variables among the leaves
    attvars::Bool = false           # one of them is attributed
    canon::Vector{Int} = Int[]      # [classes] canonical class number
    vnum::Vector{Int} = Int[]       # [vars] canonical variable number
    lnum::Vector{Int} = Int[]       # [leaves] canonical leaf number
    reached::Int = 0                # classes canonicalise() reached
    reached_leaves::Int = 0         # leaves it reached
    uses::Vector{Int} = Int[]       # [classes] how often a class is used
    named::Int = 0                  # classes that need a name
    head::Vector{Int} = Int[]       # [nodes+leaves] bucket chains
    next::Vector{Int} = Int[]       # [nodes]
    touch::Vector{Int} = Int[]      # [nodes] buckets used
    scratch::Vector{Int} = Int[]    # [nodes]
    grp::Vector{Int} = Int[]        # [nodes+1] group boundaries
    grp_next::Vector{Int} = Int[]   # [nodes+1]
    marked::Vector{Int} = Int[]     # [nodes] marked members per class
    pos_head::Vector{Int} = Int[]   # [arity] in-edges by argument
    pos_next::Vector{Int} = Int[]   # [edges]
    queue::Vector{Int} = Int[]      # [nodes] classes to re-examine
    queued::Vector{Bool} = Bool[]   # [nodes]
    qhead::Int = 0
    qtail::Int = 0
end

# ── BUILD THE GRAPH ─────────────────────────────────────────────────────────────────────────────

# PORT: pl-bisim.c build_graph
# DIVERGES: `p` is a location and the agenda is the cell agenda; returns Bool (no MEMORY_OVERFLOW). The caller must
# call `restore_graph` either way.
"Number every physically distinct compound cell reachable from location `p` in `b` (pl-bisim.c)."
function build_graph(
    ld::PL_local_data{T}, p::Int, b::Vector{bs_node}, opaque::word
)::Bool where {T}
    k, w, _ = _deref_loc(ld, p)
    (k == DU_WORD && _is_gcompound(w)) || return true       # no compound cells at all

    agenda = cell_agenda(0, 0, NTuple{2, Int}[])
    initCellAgenda!(agenda, 1, p)                           # initTermAgenda(&agenda, 1, p)
    while true
        l = nextCellAgendaNoDeRef!(agenda)                  # nextTermAgenda
        l == 0 && break
        k, w, _ = _deref_loc(ld, l)
        (k == DU_WORD && _is_gcompound(w)) || continue      # a leaf: no cell to number
        f = valPtr(w)                                       # Functor f = valueTerm(*p)
        d = ld.gstack[f]                                    # f->definition
        isTaggedIntW(d) && continue                         # seen: shared cell or a cycle
        d == opaque && continue                             # not to be taken apart
        push!(b, bs_node(f, d))
        ld.gstack[f] = consInt(Int64(length(b) - 1))        # f->definition = consInt(entriesBuffer(b, bs_node)-1)
        pushWorkCellAgenda!(agenda, arityFunctor(ld.functors, d), f + 1)
    end
    clearCellAgenda!(agenda)
    return true
end

# PORT: pl-bisim.c restore_graph
"Put the functor words back; before anything can allocate, on every exit path (pl-bisim.c)."
function restore_graph(ld::PL_local_data, b::Vector{bs_node})::Nothing
    for n in b
        ld.gstack[n.term] = n.functor
    end
    return nothing
end

# ── LEAF NUMBERING ──────────────────────────────────────────────────────────────────────────────

# PORT: pl-bisim.c leaf_order
# DIVERGES: no `ld` field (the callers pass it); `failed` is never set (see the file header, 4).
"The comparison's context (pl-bisim.c `leaf_order`): takes note if the comparison gave up."
mutable struct leaf_order
    failed::Bool
end

# ORIGINAL: upstream's `SCALAR_TO_CMP(a, b)` (pl-incl.h) on two locations.
@inline _bs_scalar_cmp(a::Int, b::Int)::Int =
    a < b ? CMP_LESS : (a > b ? CMP_GREATER : CMP_EQUAL)

# PORT: pl-bisim.c cmp_leaf
# DIVERGES: `a`, `b` are locations of the leaf cells; the standard order is `compareStandard_cells`, which cannot
# fail (no CMP_ERROR case).
"Order two leaves: variables first, by address, then by `compareStandard` (pl-bisim.c)."
function cmp_leaf(ld::PL_local_data{T}, ctx::leaf_order, a::Int, b::Int)::Int where {T}
    wa, wb = ld.gstack[a], ld.gstack[b]
    va = isVar(wa) || isAttVar(wa)
    vb = isVar(wb) || isAttVar(wb)
    va != vb && return va ? CMP_LESS : CMP_GREATER
    va && return _bs_scalar_cmp(a, b)                       # a variable is its own address
    wa == wb && return CMP_EQUAL                            # same word: certainly ==
    return compareStandard_cells(ld, a, b, false)
end

# PORT: pl-bisim.c leaf_number
"The number `number_leaves` gave the leaf at location `w`; valid once `g.leafp` is in place (pl-bisim.c)."
function leaf_number(
    ld::PL_local_data{T}, g::bs_graph, ctx::leaf_order, w::Int
)::Int where {T}
    lo, hi = 0, g.leaves
    while lo < hi                                           # binary search
        mid = (lo + hi) ÷ 2
        if cmp_leaf(ld, ctx, g.leafp[mid + 1], w) == CMP_LESS
            lo = mid + 1
        else
            hi = mid
        end
    end
    return lo
end

# PORT: pl-bisim.c number_leaves
# DIVERGES: `leaf` is the Vector of the first `nleaf` leaf locations; the deduplicated array is a new Vector
# (upstream squeezes in place); returns Bool (false: an exception is raised, which cannot happen here).
"Turn the placeholders left in `g.child` into leaf numbers; `leaf[i]` is the leaf placeholder `-i` stands for (pl-bisim.c)."
function number_leaves(
    ld::PL_local_data{T}, g::bs_graph, leaf::Vector{Int}, nleaf::Int
)::Bool where {T}
    ctx = leaf_order(false)
    g.leaves = 0
    nleaf == 0 && return true

    sorted = leaf[1:nleaf]                                  # memcpy
    sort!(sorted; lt=(x, y) -> cmp_leaf(ld, ctx, x, y) == CMP_LESS)     # sort_r

    out = Int[]
    for i in 1:nleaf                                        # squeeze out the duplicates
        if i == 1 || cmp_leaf(ld, ctx, sorted[i - 1], sorted[i]) != CMP_EQUAL
            push!(out, sorted[i])
        end
    end
    g.leaves = length(out)
    g.leafp = out                                           # g->leafp = sorted
    i = 0
    while i < g.leaves                                      # cmp_leaf() sorts variables first
        w = ld.gstack[out[i + 1]]
        (isVar(w) || isAttVar(w)) || break
        i += 1
    end
    g.vars = i

    for e in 1:g.edges                                      # rewrite the placeholders
        if g.child[e] < 0
            g.child[e] = -(leaf_number(ld, g, ctx, leaf[-g.child[e]]) + 1)
        end
    end

    return !ctx.failed                                      # false: exception already raised
end

# ── THE QUOTIENT ────────────────────────────────────────────────────────────────────────────────

# PORT: pl-bisim.c child_class
"The class an edge points at; leaves are numbered above every node class (pl-bisim.c `child_class` macro)."
@inline function child_class(g::bs_graph, e::Int)::Int
    c = g.child[e + 1]
    return c >= 0 ? g.class[c + 1] : g.nodes + (-c - 1)
end

# PORT: pl-bisim.c bs_colour
"A node with its functor word, for the initial colouring (pl-bisim.c `bs_colour`)."
struct bs_colour
    functor::word
    node::Int
end

# PORT: pl-bisim.c cmp_colour as bs_colour_lt
# DIVERGES: the sort key is (functor, node): the stable form of upstream's functor-only qsort (file header, 3).
"Order colourings by functor word (pl-bisim.c `cmp_colour`)."
@inline bs_colour_lt(a::bs_colour, b::bs_colour)::Bool =
    a.functor < b.functor || (a.functor == b.functor && a.node < b.node)

# PORT: pl-bisim.c colour_nodes
"Make the initial partition: cells that share a functor are one class (pl-bisim.c)."
function colour_nodes(g::bs_graph)::Bool
    c = Vector{bs_colour}(undef, g.nodes)
    for i in 0:(g.nodes - 1)
        c[i + 1] = bs_colour(g.node[i + 1].functor, i)
    end
    sort!(c; lt=bs_colour_lt)                               # qsort

    class = 0
    g.class_start[1] = 0
    for i in 0:(g.nodes - 1)
        if i > 0 && c[i].functor != c[i + 1].functor
            g.class_len[class + 1] = i - g.class_start[class + 1]
            class += 1
            g.class_start[class + 1] = i
        end
        g.order[i + 1] = c[i + 1].node
        g.at[c[i + 1].node + 1] = i
        g.class[c[i + 1].node + 1] = class
    end
    g.class_len[class + 1] = g.nodes - g.class_start[class + 1]
    g.classes = class + 1
    return true
end

# PORT: pl-bisim.c group_signature
"""
Reorder `order[start..start+len)` so that members with equal signatures are contiguous and leave the group
boundaries in `g.grp[0..n]`; returns the number of groups (pl-bisim.c). One argument at a time.
"""
function group_signature(g::bs_graph, start::Int, len::Int, arity::Int)::Int
    ngrp = 1
    g.grp[1] = start
    g.grp[2] = start + len

    j = 0
    while j < arity && ngrp < len
        out = 0
        g.grp_next[1] = start
        for b in 0:(ngrp - 1)
            s = g.grp[b + 1]
            e = g.grp[b + 2]
            ntouch = 0
            p = s

            if e - s <= 1
                out += 1
                g.grp_next[out + 1] = e
                continue
            end

            for i in s:(e - 1)                              # chain the members per key
                n = g.order[i + 1]
                c = g.child[g.arg[n + 1] + j + 1]
                k = c >= 0 ? LEAF_SAME : -c
                if g.head[k + 1] == NO_NODE
                    g.touch[ntouch + 1] = k
                    ntouch += 1
                end
                g.next[n + 1] = g.head[k + 1]
                g.head[k + 1] = n
            end

            for i in 0:(ntouch - 1)                         # write the chains back out
                k = g.touch[i + 1]
                n = g.head[k + 1]
                while n != NO_NODE
                    g.scratch[p + 1] = n
                    p += 1
                    n = g.next[n + 1]
                end
                g.head[k + 1] = NO_NODE
                out += 1
                g.grp_next[out + 1] = p
            end
            for i in s:(e - 1)                              # memcpy(&g->order[s], &g->scratch[s], ...)
                g.order[i + 1] = g.scratch[i + 1]
            end
        end

        ngrp = out
        for i in 0:ngrp                                     # memcpy(g->grp, g->grp_next, ...)
            g.grp[i + 1] = g.grp_next[i + 1]
        end
        j += 1
    end

    return ngrp
end

# PORT: pl-bisim.c new_class
"Make `order[start..start+len)` a class of its own (pl-bisim.c)."
function new_class(g::bs_graph, start::Int, len::Int)::Int
    c = g.classes
    g.classes += 1
    g.class_start[c + 1] = start
    g.class_len[c + 1] = len
    g.queued[c + 1] = false
    for i in start:(start + len - 1)
        g.class[g.order[i + 1] + 1] = c
        g.at[g.order[i + 1] + 1] = i
    end
    return c
end

# PORT: pl-bisim.c split_colours
"Finish the initial partition: separate cells that share a functor but hold different leaves (pl-bisim.c)."
function split_colours(ld::PL_local_data, g::bs_graph)::Nothing
    c = 0
    while c < g.classes                                     # g->classes grows as we go
        start = g.class_start[c + 1]
        len = g.class_len[c + 1]
        if len <= 1
            c += 1
            continue
        end
        arity = arityFunctor(ld.functors, g.node[g.order[start + 1] + 1].functor)
        if arity == 0
            c += 1
            continue
        end

        ngrp = group_signature(g, start, len, arity)
        if ngrp <= 1
            for i in start:(start + len - 1)                # order may have moved
                g.at[g.order[i + 1] + 1] = i
            end
            c += 1
            continue
        end

        g.class_len[c + 1] = g.grp[2] - g.grp[1]
        for i in g.grp[1]:(g.grp[2] - 1)
            g.at[g.order[i + 1] + 1] = i
        end
        for b in 1:(ngrp - 1)
            new_class(g, g.grp[b + 1], g.grp[b + 2] - g.grp[b + 1])
        end
        c += 1
    end
    return nothing
end

# ── REFINEMENT ──────────────────────────────────────────────────────────────────────────────────

# PORT: pl-bisim.c enqueue
"Queue class `class` as a splitter, once (pl-bisim.c)."
function enqueue(g::bs_graph, class::Int)::Nothing
    if !g.queued[class + 1]
        g.queued[class + 1] = true
        g.queue[g.qtail + 1] = class
        g.qtail += 1
        g.qtail == g.nodes + 1 && (g.qtail = 0)
    end
    return nothing
end

# PORT: pl-bisim.c mark_member
# DIVERGES: `touch`/`ntouch` is the caller's `Vector` and a returned count (the C `size_t *ntouch`).
"""
Move node `n` to the front of its class, among the members marked so far (pl-bisim.c); returns the new number of
touched classes.
"""
function mark_member(g::bs_graph, n::Int, touch::Vector{Int}, ntouch::Int)::Int
    c = g.class[n + 1]
    if g.marked[c + 1] == 0
        touch[ntouch + 1] = c
        ntouch += 1
    end

    to = g.class_start[c + 1] + g.marked[c + 1]
    if g.at[n + 1] != to
        other = g.order[to + 1]
        g.order[to + 1] = n
        g.order[g.at[n + 1] + 1] = other
        g.at[other + 1] = g.at[n + 1]
        g.at[n + 1] = to
    end
    g.marked[c + 1] += 1
    return ntouch
end

# PORT: pl-bisim.c refine
"Split until nothing splits any more (pl-bisim.c): the work for a splitter is proportional to the edges entering it."
function refine(g::bs_graph)::Nothing
    g.qhead = 0
    g.qtail = 0
    for i in 0:(g.classes - 1)
        g.queued[i + 1] = false
    end
    for i in 0:(g.classes - 1)
        enqueue(g, i)
    end
    for i in 0:(g.nodes - 1)
        g.marked[i + 1] = 0
    end
    for i in 0:(g.arity - 1)
        g.pos_head[i + 1] = NO_NODE
    end

    while g.qhead != g.qtail
        sp = g.queue[g.qhead + 1]
        g.qhead += 1
        npos = 0

        g.qhead == g.nodes + 1 && (g.qhead = 0)
        g.queued[sp + 1] = false

        # Sort the edges entering the splitter by the argument they come from; each argument is a separate split.
        for s in g.class_start[sp + 1]:(g.class_start[sp + 1] + g.class_len[sp + 1] - 1)
            m = g.order[s + 1]
            for e in g.pred_at[m + 1]:(g.pred_at[m + 2] - 1)
                pos = g.pred_pos[e + 1]
                if g.pos_head[pos + 1] == NO_NODE
                    g.touch[npos + 1] = pos
                    npos += 1
                end
                g.pos_next[e + 1] = g.pos_head[pos + 1]
                g.pos_head[pos + 1] = e
            end
        end

        for j in 0:(npos - 1)
            pos = g.touch[j + 1]
            ntouch = 0

            e = g.pos_head[pos + 1]
            while e != NO_NODE
                ntouch = mark_member(g, g.pred[e + 1], g.scratch, ntouch)
                e = g.pos_next[e + 1]
            end
            g.pos_head[pos + 1] = NO_NODE

            for k in 0:(ntouch - 1)
                c = g.scratch[k + 1]
                nmarked = g.marked[c + 1]
                len = g.class_len[c + 1]

                g.marked[c + 1] = 0
                nmarked == len && continue                  # the whole class: no split

                start = g.class_start[c + 1]
                g.class_start[c + 1] = start + nmarked
                g.class_len[c + 1] = len - nmarked
                nc = new_class(g, start, nmarked)

                if g.queued[c + 1]                          # still to be used as a splitter
                    enqueue(g, nc)
                elseif nmarked <= len - nmarked
                    enqueue(g, nc)
                else
                    enqueue(g, c)
                end
            end
        end
    end
    return nothing
end

# PORT: pl-bisim.c identity_partition
"Leave every cell in a class of its own: share what is physically shared and nothing else (pl-bisim.c)."
function identity_partition(g::bs_graph)::Nothing
    for i in 0:(g.nodes - 1)
        g.class[i + 1] = i
        g.order[i + 1] = i
        g.at[i + 1] = i
        g.class_start[i + 1] = i
        g.class_len[i + 1] = 1
    end
    g.classes = g.nodes
    return nothing
end

# ── SET UP ──────────────────────────────────────────────────────────────────────────────────────

# PORT: pl-bisim.c fill_edges
# DIVERGES: returns the number of leaves; `leaf` holds the leaf LOCATIONS. Runs while the functor words hold the
# node numbers: an argument that is a compound is the id of the cell it points at.
"Fill `g.arg` and `g.child` (leaf placeholders -(i+1)) and `leaf`; the number of leaves (pl-bisim.c)."
function fill_edges(ld::PL_local_data{T}, g::bs_graph, leaf::Vector{Int})::Int where {T}
    e = 0
    nleaf = 0
    for i in 0:(g.nodes - 1)
        f = g.node[i + 1].term
        arity = arityFunctor(ld.functors, g.node[i + 1].functor)
        g.arg[i + 1] = e
        for j in 0:(arity - 1)
            k, w, pa = _deref_loc(ld, f + 1 + j)            # a = &f->arguments[j]; deRef(a)
            # A compound that was not numbered is one build_graph() was told to leave alone, e.g. '$VAR'/1:
            # it counts as a leaf.
            if k == DU_WORD && _is_gcompound(w) && isTaggedIntW(ld.gstack[valPtr(w)])
                g.child[e + 1] = Int(valInt(ld.gstack[valPtr(w)]))
                e += 1
            else
                k == DU_ATTVAR && (g.attvars = true)
                nleaf += 1
                leaf[nleaf] = pa
                g.child[e + 1] = -nleaf
                e += 1
            end
        end
    end
    g.arg[g.nodes + 1] = e
    return nleaf
end

# PORT: pl-bisim.c fill_pred
"The reverse edges: `pred_at`, `pred`, `pred_pos` (pl-bisim.c)."
function fill_pred(g::bs_graph)::Nothing
    for i in 0:g.nodes
        g.pred_at[i + 1] = 0
    end
    for e in 0:(g.edges - 1)
        c = g.child[e + 1]
        c >= 0 && (g.pred_at[c + 2] += 1)
    end
    for i in 0:(g.nodes - 1)
        g.pred_at[i + 2] += g.pred_at[i + 1]
    end

    for i in 0:(g.nodes - 1)                                # memcpy(g->scratch, g->pred_at, ...)
        g.scratch[i + 1] = g.pred_at[i + 1]
    end
    for i in 0:(g.nodes - 1)
        for j in g.arg[i + 1]:(g.arg[i + 2] - 1)
            c = g.child[j + 1]
            if c >= 0
                at = g.scratch[c + 1]
                g.scratch[c + 1] += 1
                g.pred[at + 1] = i
                g.pred_pos[at + 1] = j - g.arg[i + 1]
            end
        end
    end
    return nothing
end

# PORT: pl-bisim.c alloc_graph
# DIVERGES: the arrays are Vectors (no pool); the result is `(rc, leaf)`: `rc` is `BS_OK` or `BS_GRAPH_OVERFLOW`,
# `leaf` the leaf array upstream returns through `leafp`. `nsinks`: leaves that are not arguments of a node.
"Size and allocate the arrays of `g` for the nodes in `b` (pl-bisim.c); `(BS_OK | BS_GRAPH_OVERFLOW, leaf)`."
function alloc_graph(
    ld::PL_local_data{T}, g::bs_graph, b::Vector{bs_node}, nsinks::Int
)::Tuple{Int, Vector{Int}} where {T}
    g.node = b
    g.nodes = length(b)
    g.edges = 0
    g.arity = 0
    (g.nodes == 0 && nsinks == 0) && return (BS_OK, Int[])

    for i in 1:g.nodes
        arity = arityFunctor(ld.functors, b[i].functor)
        g.edges += arity
        arity > g.arity && (g.arity = arity)
    end
    nleaf_max = g.edges + nsinks

    # An edge is held as an int: refuse a graph that does not fit rather than truncate one silently. Reaching it
    # needs a term of some 2**31 cells.
    if g.nodes > BS_INT_MAX || g.edges > BS_INT_MAX || nleaf_max > BS_INT_MAX
        return (BS_GRAPH_OVERFLOW, Int[])
    end

    # group_signature() indexes head[] with a leaf number plus one, so the buckets have to cover the leaves as
    # well as the nodes and the edges.
    buckets = g.nodes + g.edges + nleaf_max + 2

    g.arg = zeros(Int, g.nodes + 1)
    g.pred = zeros(Int, g.edges + 1)
    g.pred_pos = zeros(Int, g.edges + 1)
    g.pred_at = zeros(Int, g.nodes + 1)
    g.class = zeros(Int, g.nodes)
    g.order = zeros(Int, g.nodes)
    g.at = zeros(Int, g.nodes)
    g.class_start = zeros(Int, g.nodes)
    g.class_len = zeros(Int, g.nodes)
    g.head = fill(NO_NODE, buckets)                         # for(i<buckets) g->head[i] = NO_NODE
    g.next = zeros(Int, g.nodes)
    g.touch = zeros(Int, buckets)
    g.scratch = zeros(Int, g.nodes + 1)
    g.grp = zeros(Int, g.nodes + 1)
    g.grp_next = zeros(Int, g.nodes + 1)
    g.marked = zeros(Int, g.nodes)
    g.pos_head = zeros(Int, g.arity + 1)
    g.pos_next = zeros(Int, g.edges + 1)
    g.queue = zeros(Int, g.nodes + 1)
    g.child = zeros(Int, g.edges + 1)
    g.queued = fill(false, g.nodes)

    return (BS_OK, zeros(Int, nleaf_max + 1))
end

# PORT: pl-bisim.c setup_graph
# DIVERGES: returns `(rc, leaf, nleaf)`.
"`alloc_graph` for a term, then its edges; runs with the functor words still replaced (pl-bisim.c)."
function setup_graph(
    ld::PL_local_data{T}, g::bs_graph, b::Vector{bs_node}
)::Tuple{Int, Vector{Int}, Int} where {T}
    rc, leaf = alloc_graph(ld, g, b, 0)
    nleaf = 0
    if rc == BS_OK && g.nodes > 0
        nleaf = fill_edges(ld, g, leaf)
    end
    return (rc, leaf, nleaf)
end

# PORT: pl-bisim.c term_quotient
# DIVERGES: `g` is a fresh `bs_graph()` (upstream's memset); `p` a location; returns Bool: false with an exception
# raised (no MEMORY_OVERFLOW).
"Leave `g` holding the coarsest bisimulation of the graph of the term at location `p` (pl-bisim.c)."
function term_quotient(
    ld::PL_local_data{T}, p::Int, g::bs_graph, b::Vector{bs_node}, opaque::word,
    minimal::Bool
)::Bool where {T}
    rc = build_graph(ld, p, b, opaque)
    leaf = Int[]
    nleaf = 0
    grc = BS_OK
    if rc
        grc, leaf, nleaf = setup_graph(ld, g, b)
    end
    restore_graph(ld, b)                                    # the term is usable again

    # Now the stacks may be touched, so a graph that does not fit in an int can be reported as what it is.
    if grc == BS_GRAPH_OVERFLOW
        return PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :int))
    end
    rc || return false

    if g.nodes > 0
        number_leaves(ld, g, leaf, nleaf) || return false
        if !minimal
            identity_partition(g)
        else
            colour_nodes(g)
            fill_pred(g)
            split_colours(ld, g)
            refine(g)
        end
    end
    return true
end

# ── THE AUTOMATON ───────────────────────────────────────────────────────────────────────────────
# An automaton is a compound whose argument I is the colour of state I, and state 1 is the start state. A colour
# that is a compound gives the state one successor per argument (the number of the state it goes to); a colour that
# is not a compound makes the state a sink holding that value. State ids are argument positions: no functor word is
# overwritten here, so there is no `restore_graph` to match. A deterministic transition system: `refine` relies on it.

"No error in the automaton (pl-bisim.c `AUT_OK`)."
const AUT_OK = 0
"A successor is unbound (pl-bisim.c `AUT_INSTANTIATION`)."
const AUT_INSTANTIATION = 1
"A successor is not an integer (pl-bisim.c `AUT_NOT_INTEGER`)."
const AUT_NOT_INTEGER = 2
"A successor is out of range (pl-bisim.c `AUT_NO_STATE`)."
const AUT_NO_STATE = 3

# PORT: pl-bisim.c bs_automaton
# DIVERGES: `error` is an `Int` (the `aut_error` constants above).
"An automaton read into node ids (pl-bisim.c `bs_automaton`)."
Base.@kwdef mutable struct bs_automaton
    states::Int = 0                 # the arity of the automaton
    state::Vector{Int} = Int[]      # [states] node id, or -(leaf+1)
    sinks::Int = 0                  # how many states are sinks
    error::Int = AUT_OK
    at::Int = 0                     # the state it is in, 1..states
    arg::Int = 0                    # which of its arguments, 1..
end

# ORIGINAL: the Prolog integer `n` as a cell's word, whatever the term type tags (upstream `consInt`).
@inline function _bs_int_word(ld::PL_local_data{T}, n::Int)::word where {T}
    return _gnd_word!(ld, mk_gnd(T, Int64(n)))
end

# ORIGINAL: `makeRefG(a) if canBind(*a) else *a` for the leaf at location `a` (a cell of the term, not a slot).
@inline function _bs_leaf_word(ld::PL_local_data, a::Int)::word
    w = ld.gstack[a]
    return (isVar(w) || isAttVar(w)) ? makeRefG(a) : w
end

# PORT: pl-bisim.c fill_edges_automaton
# DIVERGES: `f` is the position of the automaton's functor word (upstream's `w`, a pointer to the compound's
# cell); a successor's integer is read as `PL_get_integer` does on the words (a type that tags no integer keeps it
# in the value table: `_untagged_int`).
"Fill `g.arg`/`g.child` from the automaton at `f`; false and `aut.error` set when a successor is not a state (pl-bisim.c)."
function fill_edges_automaton(
    ld::PL_local_data{T}, f::Int, g::bs_graph, aut::bs_automaton
)::Bool where {T}
    e = 0
    for i in 0:(aut.states - 1)
        k, w, _ = _deref_loc(ld, f + 1 + i)                 # c = &f->arguments[i]; deRef(c)
        aut.state[i + 1] < 0 && continue                    # a sink: no successors
        node = aut.state[i + 1]
        cf = valPtr(w)                                      # cf = valueTerm(*c)
        arity = arityFunctor(ld.functors, g.node[node + 1].functor)
        g.arg[node + 1] = e

        for j in 0:(arity - 1)
            ka, wa, _ = _deref_loc(ld, cf + 1 + j)          # a = &cf->arguments[j]; deRef(a)
            aut.at = i + 1
            aut.arg = j + 1

            if !(ka == DU_VALUE && (isTaggedIntW(wa) || isInteger(_indirect_value(ld, wa))))   # !isInteger(*a)
                aut.error =
                    (ka == DU_CELL || ka == DU_ATTVAR) ? AUT_INSTANTIATION : AUT_NOT_INTEGER
                return false
            end
            kv = isTaggedIntW(wa) ? valInt(wa) : _untagged_int(ld, wa)
            if kv === nothing || kv < 1 || kv > aut.states  # a bignum is out of range too
                aut.error = AUT_NO_STATE
                return false
            end
            g.child[e + 1] = aut.state[kv]                  # aut->state[k-1]
            e += 1
        end
    end
    g.arg[g.nodes + 1] = e
    aut.error = AUT_OK
    return true
end

# PORT: pl-bisim.c build_automaton
# DIVERGES: `f` is the functor word's position; returns `(rc, leaf, nleaf)` with `rc` `BS_OK` or `BS_GRAPH_OVERFLOW`
# (no MEMORY_OVERFLOW); a malformed automaton is `BS_OK` with `aut.error` set, as upstream's `true`.
"Turn the automaton at functor position `f` into a graph (pl-bisim.c)."
function build_automaton(
    ld::PL_local_data{T}, f::Int, g::bs_graph, b::Vector{bs_node}, aut::bs_automaton
)::Tuple{Int, Vector{Int}, Int} where {T}
    aut.states = arityFunctor(ld.functors, ld.gstack[f])
    aut.state = zeros(Int, aut.states)
    nsink = 0

    # Hand the node ids out in state order, so that state 1 is node 0 if it is not a sink: build_minimal() and
    # canonicalise() root at node 0, which is how the start state stays the start state.
    for i in 0:(aut.states - 1)
        k, w, _ = _deref_loc(ld, f + 1 + i)
        if !(k == DU_WORD && _is_gcompound(w))              # !isTerm(*c)
            k == DU_ATTVAR && (g.attvars = true)
            nsink += 1
            aut.state[i + 1] = -nsink
            continue
        end
        cf = valPtr(w)
        push!(b, bs_node(cf, ld.gstack[cf]))
        aut.state[i + 1] = length(b) - 1
    end
    aut.sinks = nsink

    rc, leaf = alloc_graph(ld, g, b, nsink)
    rc == BS_OK || return (rc, leaf, 0)

    nsink = 0
    for i in 0:(aut.states - 1)                             # the sinks, in the same order
        if aut.state[i + 1] < 0
            _, _, pc = _deref_loc(ld, f + 1 + i)
            nsink += 1
            leaf[nsink] = pc
        end
    end

    fill_edges_automaton(ld, f, g, aut) || return (BS_OK, leaf, nsink)   # aut.error says what is wrong
    fill_pred(g)
    return (BS_OK, leaf, nsink)
end

# PORT: pl-bisim.c resolve_states
"Rewrite the leaf placeholders left in `aut.state` the way `number_leaves` did for `g.child` (pl-bisim.c)."
function resolve_states(
    ld::PL_local_data{T}, g::bs_graph, aut::bs_automaton, leaf::Vector{Int}
)::Bool where {T}
    ctx = leaf_order(false)
    for i in 1:aut.states
        if aut.state[i] < 0
            aut.state[i] = -(leaf_number(ld, g, ctx, leaf[-aut.state[i]]) + 1)
        end
    end
    return !ctx.failed
end

# PORT: pl-bisim.c automaton_quotient
# DIVERGES: `f` is the functor word's position; `g`, `aut` are fresh (upstream's memsets); returns Bool, with
# `aut.error` for an automaton that does not parse.
"`term_quotient` for an automaton at functor position `f` (pl-bisim.c)."
function automaton_quotient(
    ld::PL_local_data{T}, f::Int, g::bs_graph, b::Vector{bs_node}, aut::bs_automaton,
    minimal::Bool
)::Bool where {T}
    rc, leaf, nleaf = build_automaton(ld, f, g, b, aut)
    if rc == BS_GRAPH_OVERFLOW
        return PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :int))
    end

    if aut.error == AUT_OK
        number_leaves(ld, g, leaf, nleaf) || return false
        resolve_states(ld, g, aut, leaf) || return false

        if g.nodes > 0
            if !minimal
                identity_partition(g)
            else
                colour_nodes(g)
                split_colours(ld, g)
                refine(g)
            end
        end
    end
    return true
end

# PORT: pl-bisim.c automaton_error
"Raise the error `aut.error` names for the automaton `A`, once the graph is gone (pl-bisim.c)."
function automaton_error(ld::PL_local_data{T}, A::term_t, aut::bs_automaton)::Bool where {T}
    s = PL_new_term_ref(ld)
    x = PL_new_term_ref(ld)
    (_PL_get_arg(ld, aut.at, A, s) && _PL_get_arg(ld, aut.arg, s, x)) || return false

    aut.error == AUT_INSTANTIATION && return PL_error(ld, ERR_INSTANTIATION)
    aut.error == AUT_NOT_INTEGER && return PL_type_error(ld, "integer", x)
    aut.error == AUT_NO_STATE && return PL_error(ld, ERR_EXISTENCE, mk_sym(T, :state), x)
    @assert false                                           # AUT_OK: assert(0)
    return false
end

# PORT: pl-bisim.c get_automaton
# DIVERGES: returns the position of the compound's functor word, or `nothing` after raising (upstream's `*wp` is
# the pointer to the compound's cell).
"Check that `A` is an automaton and answer where its functor word is (pl-bisim.c): only the arity matters."
function get_automaton(ld::PL_local_data{T}, A::term_t)::Union{Nothing, Int} where {T}
    k, w, _ = _deref_loc(ld, -(A + 1))                      # w = valTermRef(A); deRef(w)
    if k == DU_WORD && _is_gcompound(w)
        f = valPtr(w)
        if arityFunctor(ld.functors, ld.gstack[f]) == 0
            PL_domain_error(ld, "automaton", A)
            return nothing
        end
        return f
    end
    if k == DU_CELL || k == DU_ATTVAR                       # canBind(*w)
        PL_error(ld, ERR_INSTANTIATION)
        return nothing
    end
    PL_type_error(ld, "compound", A)
    return nothing
end

# ── CANONICAL NUMBERING ─────────────────────────────────────────────────────────────────────────
# The quotient is unique but the numbers on it are not; two terms that are =@= must come out with the same
# numbers, or the answer is no use as a key. So: walk the quotient depth first from the root (node 0), arguments
# left to right, and number each class the first time it is reached; variables the first time the class holding
# them is reached, left to right. Both depend on nothing but the shape of the quotient.

# ORIGINAL: upstream's `consCompound(p)` (pl-data.h) for a global position.
@inline _bs_compound(p::Int)::word = consPtr(p, TAG_COMPOUND | STG_GLOBAL)

# PORT: pl-bisim.c canonicalise
# DIVERGES: returns true always (no MEMORY_OVERFLOW; the arrays are Vectors, not pooled).
"Number the classes, variables and leaves canonically from the root; sets `reached`, `reached_leaves` (pl-bisim.c)."
function canonicalise(ld::PL_local_data, g::bs_graph)::Bool
    top = 0
    next = 1
    vnext = 1
    lnext = 1
    g.canon = zeros(Int, g.classes)
    g.vnum = zeros(Int, g.vars + 1)
    g.lnum = zeros(Int, g.leaves + 1)
    stack = zeros(Int, g.edges + 2)

    stack[top + 1] = g.class[1]                             # the root cell is node 0
    top += 1
    while top > 0
        top -= 1
        c = stack[top + 1]
        g.canon[c + 1] != 0 && continue
        g.canon[c + 1] = next
        next += 1

        rep = g.order[g.class_start[c + 1] + 1]
        arity = arityFunctor(ld.functors, g.node[rep + 1].functor)

        for j in 0:(arity - 1)                              # variables, left to right
            ch = g.child[g.arg[rep + 1] + j + 1]
            if ch < 0
                leaf = -ch - 1
                if leaf < g.vars && g.vnum[leaf + 1] == 0
                    g.vnum[leaf + 1] = vnext
                    vnext += 1
                end
                if g.lnum[leaf + 1] == 0
                    g.lnum[leaf + 1] = lnext
                    lnext += 1
                end
            end
        end
        for j in (arity - 1):-1:0                           # push right to left: they come off left to right
            ch = g.child[g.arg[rep + 1] + j + 1]
            if ch >= 0
                stack[top + 1] = g.class[ch + 1]
                top += 1
            end
        end
    end

    # Every class of a term is reachable from its root; an automaton may name states its start state cannot reach,
    # and those keep canon[c] == 0.
    g.reached = next - 1
    g.reached_leaves = lnext - 1
    return true
end

# ── BUILD THE RESULT ────────────────────────────────────────────────────────────────────────────

# PORT: pl-bisim.c canonical_size
"The global cells `build_canonical` writes (pl-bisim.c)."
function canonical_size(ld::PL_local_data, g::bs_graph)::Int
    need = 3 * g.classes + 2 * g.vars
    for c in 0:(g.classes - 1)
        rep = g.order[g.class_start[c + 1] + 1]
        need += 1 + arityFunctor(ld.functors, g.node[rep + 1].functor)
    end
    return need
end

# PORT: pl-bisim.c build_canonical
# DIVERGES: `base` is a global position, the result the form's word; the arrays are Vectors.
"""
Write the quotient out as a ground, acyclic term at global position `base`: a list of the classes in canonical
order, each the class's functor applied to its arguments, a cell argument the canonical number of its class, a
variable `'\$VAR'(N)`, anything else the leaf itself (pl-bisim.c). Returns the word of the list.
"""
function build_canonical(ld::PL_local_data{T}, g::bs_graph, base::Int)::word where {T}
    p = base
    ccell = zeros(Int, g.classes)
    bycanon = zeros(Int, g.classes)
    vcell = zeros(Int, g.vars)
    isovar1 = lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, Symbol("\$VAR"))), 1)

    for i in 0:(g.classes - 1)
        bycanon[g.canon[i + 1]] = i
    end

    for i in 0:(g.classes - 1)                              # hand out the cells
        rep = g.order[g.class_start[bycanon[i + 1] + 1] + 1]
        ccell[i + 1] = p
        p += 1 + arityFunctor(ld.functors, g.node[rep + 1].functor)
    end
    for i in 0:(g.vars - 1)
        vcell[i + 1] = p
        p += 2
    end

    for i in 0:(g.classes - 1)
        rep = g.order[g.class_start[bycanon[i + 1] + 1] + 1]
        arity = arityFunctor(ld.functors, g.node[rep + 1].functor)

        ld.gstack[ccell[i + 1]] = g.node[rep + 1].functor
        for j in 0:(arity - 1)
            ch = g.child[g.arg[rep + 1] + j + 1]
            if ch >= 0
                ld.gstack[ccell[i + 1] + 1 + j] = _bs_int_word(
                    ld, g.canon[g.class[ch + 1] + 1]
                )
            else
                leaf = -ch - 1
                if leaf < g.vars
                    ld.gstack[ccell[i + 1] + 1 + j] = _bs_compound(vcell[g.vnum[leaf + 1]])
                else
                    ld.gstack[ccell[i + 1] + 1 + j] = ld.gstack[g.leafp[leaf + 1]]
                end
            end
        end
    end

    for i in 0:(g.vars - 1)
        ld.gstack[vcell[i + 1]] = isovar1
        ld.gstack[vcell[i + 1] + 1] = _bs_int_word(ld, i + 1)
    end

    form = g.classes > 0 ? _bs_compound(p) : ld.atom_nil_w
    for i in 0:(g.classes - 1)                              # the list holding them together
        ld.gstack[p] = ld.functor_dot2
        ld.gstack[p + 1] = _bs_compound(ccell[i + 1])
        ld.gstack[p + 2] = i + 1 < g.classes ? _bs_compound(p + 3) : ld.atom_nil_w
        p += 3
    end
    return form
end

# PORT: pl-bisim.c minimal_size
"The global cells the quotient needs: one functor plus its arguments for every class (pl-bisim.c)."
function minimal_size(ld::PL_local_data, g::bs_graph)::Int
    need = 0
    for c in 0:(g.classes - 1)
        rep = g.order[g.class_start[c + 1] + 1]
        need += 1 + arityFunctor(ld.functors, g.node[rep + 1].functor)
    end
    return need
end

# PORT: pl-bisim.c build_minimal
# DIVERGES: `base` is a global position, the result the word denoting the class of the root.
"Write the quotient at global position `base`, one cell per class (pl-bisim.c); the word of the root's class."
function build_minimal(ld::PL_local_data, g::bs_graph, base::Int)::word
    p = base
    cell = zeros(Int, g.classes)

    for c in 0:(g.classes - 1)                              # hand out the cells
        rep = g.order[g.class_start[c + 1] + 1]
        cell[c + 1] = p
        p += 1 + arityFunctor(ld.functors, g.node[rep + 1].functor)
    end

    for c in 0:(g.classes - 1)
        rep = g.order[g.class_start[c + 1] + 1]
        arity = arityFunctor(ld.functors, g.node[rep + 1].functor)

        ld.gstack[cell[c + 1]] = g.node[rep + 1].functor
        for j in 0:(arity - 1)
            ch = g.child[g.arg[rep + 1] + j + 1]
            if ch >= 0                                      # a cell: point at its class
                ld.gstack[cell[c + 1] + 1 + j] = _bs_compound(cell[g.class[ch + 1] + 1])
            else                                            # a leaf: take it as it stands
                ld.gstack[cell[c + 1] + 1 + j] = _bs_leaf_word(ld, g.leafp[-ch])
            end
        end
    end

    return _bs_compound(cell[g.class[1] + 1])
end

# PORT: pl-bisim.c automaton_size
"The global cells `build_automaton_result` writes (pl-bisim.c)."
function automaton_size(ld::PL_local_data, g::bs_graph)::Int
    need = 1 + g.reached + g.reached_leaves
    for c in 0:(g.classes - 1)
        if g.canon[c + 1] != 0
            rep = g.order[g.class_start[c + 1] + 1]
            need += 1 + arityFunctor(ld.functors, g.node[rep + 1].functor)
        end
    end
    return need
end

# PORT: pl-bisim.c build_automaton_result
# DIVERGES: `base` is a global position, the result the automaton's word.
"""
Write the quotient out as an automaton at `base`: argument I is the colour of state I; a class its functor applied to
the numbers of the states its arguments go to, a leaf a state holding the leaf (pl-bisim.c). State 1 is the root;
a state it could not reach is left out.
"""
function build_automaton_result(
    ld::PL_local_data{T}, g::bs_graph, base::Int
)::word where {T}
    states = g.reached + g.reached_leaves
    a = base
    p = base + 1 + states

    ld.gstack[a] = lookupFunctorDef(
        ld.functors, _atom_word!(ld, mk_sym(T, :automaton)), states
    )

    for c in 0:(g.classes - 1)
        g.canon[c + 1] == 0 && continue                     # the root cannot reach it

        rep = g.order[g.class_start[c + 1] + 1]
        arity = arityFunctor(ld.functors, g.node[rep + 1].functor)

        ld.gstack[a + g.canon[c + 1]] = _bs_compound(p)
        ld.gstack[p] = g.node[rep + 1].functor
        for j in 0:(arity - 1)
            ch = g.child[g.arg[rep + 1] + j + 1]
            ld.gstack[p + 1 + j] = _bs_int_word(
                ld, ch >= 0 ? g.canon[g.class[ch + 1] + 1] : g.reached + g.lnum[-ch]
            )
        end
        p += 1 + arity
    end

    for i in 0:(g.leaves - 1)                               # the sinks
        if g.lnum[i + 1] != 0
            ld.gstack[a + g.reached + g.lnum[i + 1]] = _bs_leaf_word(ld, g.leafp[i + 1])
        end
    end

    return _bs_compound(a)
end

# PORT: pl-bisim.c build_map
# DIVERGES: `base` is a global position, the result the map's word.
"What became of each state of the input: the number of the state it collapsed into, 0 if unreachable (pl-bisim.c)."
function build_map(
    ld::PL_local_data{T}, g::bs_graph, aut::bs_automaton, base::Int
)::word where {T}
    m = base
    ld.gstack[m] = lookupFunctorDef(
        ld.functors, _atom_word!(ld, mk_sym(T, :map)), aut.states
    )
    for i in 0:(aut.states - 1)
        st = aut.state[i + 1]
        if st >= 0
            to = g.canon[g.class[st + 1] + 1]
        else
            to = g.lnum[-st] != 0 ? g.reached + g.lnum[-st] : 0
        end
        ld.gstack[m + 1 + i] = _bs_int_word(ld, to)
    end
    return _bs_compound(m)
end

# ── FACTORIZED FORM ─────────────────────────────────────────────────────────────────────────────
# A class needs a name when it is used more than once, counting the root as a use: exactly enough to break every
# cycle, so the skeleton stays finite. A class used once is written where it is used.

# PORT: pl-bisim.c name_classes
"Count the uses of each class and how many need a name (pl-bisim.c)."
function name_classes(ld::PL_local_data, g::bs_graph)::Bool
    g.uses = zeros(Int, g.classes)
    g.uses[g.class[1] + 1] += 1                             # the root is a use

    for c in 0:(g.classes - 1)
        rep = g.order[g.class_start[c + 1] + 1]
        arity = arityFunctor(ld.functors, g.node[rep + 1].functor)
        for j in 0:(arity - 1)
            ch = g.child[g.arg[rep + 1] + j + 1]
            ch >= 0 && (g.uses[g.class[ch + 1] + 1] += 1)
        end
    end

    g.named = 0
    for c in 0:(g.classes - 1)
        g.uses[c + 1] > 1 && (g.named += 1)
    end
    return true
end

# PORT: pl-bisim.c factorized_size
"The global cells `build_factorized` writes (pl-bisim.c)."
function factorized_size(ld::PL_local_data, g::bs_graph)::Int
    need = g.named * (1 + 3 + 3)                            # variable, =/2, list cell
    for c in 0:(g.classes - 1)
        rep = g.order[g.class_start[c + 1] + 1]
        need += 1 + arityFunctor(ld.functors, g.node[rep + 1].functor)
    end
    return need
end

# PORT: pl-bisim.c build_factorized
# DIVERGES: `base` is a global position; returns `(skeleton word, substitution word)`; `classes == 0` (upstream's
# false) cannot happen: the callers answer a term with no cells before. A fresh variable is a cell holding 0.
"""
Write one cell per class at `base`; a class used once is where it is used, a named class a fresh variable and its cell
the right hand side of an equation, in canonical order (pl-bisim.c).
"""
function build_factorized(
    ld::PL_local_data{T}, g::bs_graph, base::Int
)::Tuple{word, word} where {T}
    p = base
    root = g.class[1]
    cell = zeros(Int, g.classes)
    var = zeros(Int, g.classes)                             # 0: no variable (upstream NULL)
    bycanon = zeros(Int, g.classes)
    equals2 = lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :(=))), 2)

    for c in 0:(g.classes - 1)
        bycanon[g.canon[c + 1]] = c
    end

    for c in 0:(g.classes - 1)                              # hand out the cells
        rep = g.order[g.class_start[c + 1] + 1]
        cell[c + 1] = p
        p += 1 + arityFunctor(ld.functors, g.node[rep + 1].functor)
    end
    for i in 0:(g.classes - 1)                              # and a variable per named class
        cc = bycanon[i + 1]
        if g.uses[cc + 1] > 1
            var[cc + 1] = p
            p += 1
            ld.gstack[var[cc + 1]] = word(0)                # setVar
        end
    end

    for c in 0:(g.classes - 1)
        rep = g.order[g.class_start[c + 1] + 1]
        arity = arityFunctor(ld.functors, g.node[rep + 1].functor)

        ld.gstack[cell[c + 1]] = g.node[rep + 1].functor
        for j in 0:(arity - 1)
            ch = g.child[g.arg[rep + 1] + j + 1]
            if ch >= 0
                d = g.class[ch + 1]
                ld.gstack[cell[c + 1] + 1 + j] =
                    var[d + 1] != 0 ? makeRefG(var[d + 1]) : _bs_compound(cell[d + 1])
            else
                ld.gstack[cell[c + 1] + 1 + j] = _bs_leaf_word(ld, g.leafp[-ch])
            end
        end
    end

    skel = var[root + 1] != 0 ? makeRefG(var[root + 1]) : _bs_compound(cell[root + 1])

    subst = ld.atom_nil_w                                   # the equations, canonical order
    for i in (g.classes - 1):-1:0
        cc = bycanon[i + 1]
        if var[cc + 1] != 0
            eq = p
            ld.gstack[eq] = equals2
            ld.gstack[eq + 1] = makeRefG(var[cc + 1])
            ld.gstack[eq + 2] = _bs_compound(cell[cc + 1])
            p += 3

            ld.gstack[p] = ld.functor_dot2
            ld.gstack[p + 1] = _bs_compound(eq)
            ld.gstack[p + 2] = subst
            subst = _bs_compound(p)
            p += 3
        end
    end
    return (skel, subst)
end

# ── PREDICATES ──────────────────────────────────────────────────────────────────────────────────

# ORIGINAL: upstream's `for(;;) { ...; if ( gTop + need > gMax ) rc = GLOBAL_OVERFLOW; ...; makeMoreStackSpace }`
# retry loop, reduced: the global stack grows on demand, so the request is checked against the limit
# (`ensureGlobalSpace`, which raises the overflow) and granted at once; the graph's locations stay valid. Returns the
# position of the `need` cells, 0 with an exception raised.
"`need` fresh global cells for a result, or 0 after raising the overflow."
function _bs_alloc(ld::PL_local_data, need::Int)::Int
    ensureGlobalSpace(ld, need) || return 0
    base = allocGlobalNoShift(ld, need)
    if base == 0
        raiseStackOverflow(ld, GLOBAL_OVERFLOW)
        return 0
    end
    return base
end

# ORIGINAL: `FUNCTOR_isovar1`, `FUNCTOR_automaton1`, ATOM_map functors, looked up per call.
@inline function _bs_functor(ld::PL_local_data{T}, name::Symbol, arity::Int)::word where {T}
    return lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, name)), arity)
end

# PORT: pl-bisim.c term_minimal as pl_term_minimal2_va
function pl_term_minimal2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    result = PL_new_term_ref(ld)
    b = bs_node[]
    g = bs_graph()
    term_quotient(ld, -(A1 + 1), g, b, word(0), true) || return FFALSE
    g.nodes == 0 && return PL_unify(ld, A2, A1) ? FTRUE : FFALSE    # nothing to share
    base = _bs_alloc(ld, minimal_size(ld, g))
    base == 0 && return FFALSE
    ld.slots[result + 1] = build_minimal(ld, g, base)               # *valTermRef(result) = w
    return PL_unify(ld, A2, result) ? FTRUE : FFALSE
end

# PORT: pl-bisim.c term_canonical_form
# DIVERGES: returns `(ok, attvars)` where upstream writes `*attvars`.
function term_canonical_form(
    ld::PL_local_data{T}, t::term_t, form::term_t
)::Tuple{Bool, Bool} where {T}
    result = PL_new_term_ref(ld)
    b = bs_node[]
    g = bs_graph()
    term_quotient(ld, -(t + 1), g, b, word(0), true) || return (false, false)
    attvars = g.attvars
    g.nodes == 0 && return (PL_unify(ld, form, t), attvars)         # no cells: the term is its own form
    canonicalise(ld, g)
    base = _bs_alloc(ld, canonical_size(ld, g))
    base == 0 && return (false, attvars)
    ld.slots[result + 1] = build_canonical(ld, g, base)
    return (PL_unify(ld, form, result), attvars)
end

# PORT: pl-bisim.c term_canonical_form_pred as pl_term_canonical_form2_va
function pl_term_canonical_form2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    ok, _ = term_canonical_form(ld, PL__t0, PL__t0 + 1)
    return ok ? FTRUE : FFALSE
end

# PORT: pl-bisim.c do_term_factorized
function do_term_factorized(
    ld::PL_local_data{T}, t::term_t, skeleton::term_t, substitution::term_t, opaque::word,
    minimal::Bool
)::Bool where {T}
    skel = PL_new_term_ref(ld)
    subst = PL_new_term_ref(ld)
    b = bs_node[]
    g = bs_graph()
    term_quotient(ld, -(t + 1), g, b, opaque, minimal) || return false
    if g.nodes == 0                                         # no cells: nothing to factor out
        return PL_unify(ld, skeleton, t) && PL_unify_nil(ld, substitution)
    end
    canonicalise(ld, g)
    name_classes(ld, g)
    base = _bs_alloc(ld, factorized_size(ld, g))
    base == 0 && return false
    s, e = build_factorized(ld, g, base)
    ld.slots[skel + 1] = s
    ld.slots[subst + 1] = e
    return PL_unify(ld, skeleton, skel) && PL_unify(ld, substitution, subst)
end

# PORT: pl-bisim.c factorized_options
const factorized_options = (
    PL_option_t(:minimal, OPT_BOOL), PL_option_t(:dollar_var, OPT_BOOL)
)

# PORT: pl-bisim.c term_factorized as pl_term_factorized3_va
function pl_term_factorized3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    ok = do_term_factorized(
        ld, PL__t0, PL__t0 + 1, PL__t0 + 2, _bs_functor(ld, Symbol("\$VAR"), 1), true
    )
    return ok ? FTRUE : FFALSE
end

# PORT: pl-bisim.c term_factorized4 as pl_term_factorized4_va
# DIVERGES: the options' values are returned by `PL_scan_options` (`nothing`: the default, true).
function pl_term_factorized4_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    vals = PL_scan_options(ld, PL__t0 + 3, 0, "factorize_option", factorized_options)
    vals === nothing && return FFALSE
    minimal = vals[1] === nothing ? true : (vals[1]::Bool)
    dollar_var = vals[2] === nothing ? true : (vals[2]::Bool)
    opaque = dollar_var ? _bs_functor(ld, Symbol("\$VAR"), 1) : word(0)
    return if do_term_factorized(ld, PL__t0, PL__t0 + 1, PL__t0 + 2, opaque, minimal)
        FTRUE
    else
        FFALSE
    end
end

# PORT: pl-bisim.c term_to_automaton
function term_to_automaton(ld::PL_local_data{T}, Tt::term_t, A::term_t)::Bool where {T}
    result = PL_new_term_ref(ld)
    b = bs_node[]
    g = bs_graph()
    term_quotient(ld, -(Tt + 1), g, b, word(0), false) || return false
    if g.nodes == 0                                         # a leaf: one state, holding it
        f = PL_new_term_ref(ld)                             # PL_unify_term(A, PL_FUNCTOR, FUNCTOR_automaton1, PL_TERM, T)
        PL_cons_functor(ld, f, _bs_functor(ld, :automaton, 1), Tt)
        return PL_unify(ld, A, f)
    end
    canonicalise(ld, g)
    base = _bs_alloc(ld, automaton_size(ld, g))
    base == 0 && return false
    ld.slots[result + 1] = build_automaton_result(ld, g, base)
    return PL_unify(ld, A, result)
end

# PORT: pl-bisim.c automaton_to_term
function automaton_to_term(ld::PL_local_data{T}, A::term_t, Tt::term_t)::Bool where {T}
    result = PL_new_term_ref(ld)
    f = get_automaton(ld, A)
    f === nothing && return false
    b = bs_node[]
    g = bs_graph()
    aut = bs_automaton()
    automaton_quotient(ld, f, g, b, aut, false) || return false
    aut.error == AUT_OK || return automaton_error(ld, A, aut)
    if aut.state[1] < 0                                     # the start state is a sink
        ld.slots[result + 1] = _bs_leaf_word(ld, g.leafp[-aut.state[1]])
    else
        base = _bs_alloc(ld, minimal_size(ld, g))
        base == 0 && return false
        ld.slots[result + 1] = build_minimal(ld, g, base)
    end
    return PL_unify(ld, Tt, result)
end

# PORT: pl-bisim.c term_automaton as pl_term_automaton2_va
function pl_term_automaton2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    k, _, _ = _deref_loc(ld, -(A2 + 1))                     # p = valTermRef(A2); deRef(p)
    ok = if (k == DU_CELL || k == DU_ATTVAR)
        term_to_automaton(ld, A1, A2)
    else
        automaton_to_term(ld, A2, A1)
    end
    return ok ? FTRUE : FFALSE
end

# PORT: pl-bisim.c minimal_automaton_size
function minimal_automaton_size(
    ld::PL_local_data, g::bs_graph, aut::bs_automaton, sink::Bool, map::Bool
)::Int
    need = sink ? 2 : automaton_size(ld, g)
    map && (need += 1 + aut.states)
    return need
end

# PORT: pl-bisim.c build_minimal_automaton
# DIVERGES: `base` is a global position; returns `(min, map)` (`map` 0 when not asked for).
function build_minimal_automaton(
    ld::PL_local_data{T}, g::bs_graph, aut::bs_automaton, sink::Bool, base::Int,
    wantmap::Bool
)::Tuple{word, word} where {T}
    p = base
    min = word(0)
    map = word(0)
    if sink                         # the start state is a sink: the automaton denotes a leaf
        ld.gstack[p] = _bs_functor(ld, :automaton, 1)
        ld.gstack[p + 1] = _bs_leaf_word(ld, g.leafp[-aut.state[1]])
        min = _bs_compound(p)
        p += 2
    else
        min = build_automaton_result(ld, g, p)
        p += automaton_size(ld, g)
    end
    if wantmap
        if sink
            ld.gstack[p] = _bs_functor(ld, :map, aut.states)
            for i in 0:(aut.states - 1)
                ld.gstack[p + 1 + i] = _bs_int_word(
                    ld, aut.state[i + 1] == aut.state[1] ? 1 : 0
                )
            end
            map = _bs_compound(p)
        else
            map = build_map(ld, g, aut, p)
        end
    end
    return (min, map)
end

# PORT: pl-bisim.c do_automaton_minimal
function do_automaton_minimal(
    ld::PL_local_data{T}, A::term_t, Min::term_t, Map::Union{Nothing, term_t}
)::Bool where {T}
    rmin = PL_new_term_ref(ld)
    rmap = Map === nothing ? 0 : PL_new_term_ref(ld)
    f = get_automaton(ld, A)
    f === nothing && return false
    b = bs_node[]
    g = bs_graph()
    aut = bs_automaton()
    automaton_quotient(ld, f, g, b, aut, true) || return false
    aut.error == AUT_OK || return automaton_error(ld, A, aut)
    sink = aut.state[1] < 0
    sink || canonicalise(ld, g)
    base = _bs_alloc(ld, minimal_automaton_size(ld, g, aut, sink, Map !== nothing))
    base == 0 && return false
    m, mp = build_minimal_automaton(ld, g, aut, sink, base, Map !== nothing)
    ld.slots[rmin + 1] = m
    Map === nothing || (ld.slots[rmap + 1] = mp)
    return PL_unify(ld, Min, rmin) && (Map === nothing || PL_unify(ld, Map, rmap))
end

# PORT: pl-bisim.c automaton_minimal as pl_automaton_minimal2_va
function pl_automaton_minimal2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return do_automaton_minimal(ld, PL__t0, PL__t0 + 1, nothing) ? FTRUE : FFALSE
end
# PORT: pl-bisim.c automaton_minimal3 as pl_automaton_minimal3_va
function pl_automaton_minimal3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return do_automaton_minimal(ld, PL__t0, PL__t0 + 1, PL__t0 + 2) ? FTRUE : FFALSE
end

# PORT: pl-bisim.c BeginPredDefs as PL_predicates_from_bisim
const PL_predicates_from_bisim = (
    PL_extension("term_minimal", 2, pl_term_minimal2_va, PL_FA_VARARGS),
    PL_extension("\$term_canonical_form", 2, pl_term_canonical_form2_va, PL_FA_VARARGS),
    PL_extension("term_factorized", 3, pl_term_factorized3_va, PL_FA_VARARGS),
    PL_extension("term_factorized", 4, pl_term_factorized4_va, PL_FA_VARARGS),
    PL_extension("term_automaton", 2, pl_term_automaton2_va, PL_FA_VARARGS),
    PL_extension("automaton_minimal", 2, pl_automaton_minimal2_va, PL_FA_VARARGS),
    PL_extension("automaton_minimal", 3, pl_automaton_minimal3_va, PL_FA_VARARGS)
)
