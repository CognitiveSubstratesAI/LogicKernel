# UPSTREAM: swipl-devel src/pl-variant.c @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2016, Kuniaki Mukai
#
# VARIANT CHECKING — `=@=`: two terms are variants when they are equal up to a consistent,
# one-to-one renaming of their variables. SWI-Prolog's pl-variant.c, ported: the same argument
# agenda (`argPairs`, `push_args`, `next_arg`), the same two-way variable correspondence (a left
# variable maps to exactly one right variable and back — upstream's node fields `a` and `b`), the
# same quick tests in `is_variant_ptr`.
#
# TWO ENTRIES. Without `ld`, for RESOLVED terms (values): DIVERGES — upstream numbers COMPOUND cells
# too (`term_id`, `Root`, `isomorphic`), so that cyclic terms terminate and a compound met twice is
# compared by identity of its partner; a resolved term is a finite tree, so this entry walks every
# compound instead — for a finite term with shared subterms the answer is the same (a shared left
# subterm met again maps its variables through the same correspondence, which fails exactly when
# upstream's `isomorphic` does); variables are found by `var_key` in two maps where upstream
# overwrites the variable's cell. On the CELLS (`is_variant_ptr_cells`, at the end of the file), where
# a term can be a rational tree: upstream's numbering is ported, the numbers in a side vector.

# PORT: pl-variant.c aWork
"A pair of compounds whose arguments are being compared (pl-variant.c `aWork`)."
struct aWork{T}
    left::T             # left term (its arguments, from `off`)
    right::T            # right term
    off::Int            # child index of argument 0; 0 for the initial pair of whole terms
    arg::Int            # next argument (0-based)
    arity::Int          # its number of arguments
end

# PORT: pl-variant.c argPairs
"The agenda of argument pairs still to compare (pl-variant.c `argPairs`)."
mutable struct argPairs{T}
    work::aWork{T}                  # current work
    stack::Vector{aWork{T}}
end

# PORT: pl-variant.c push_start_args
"Start the agenda on one pair (pl-variant.c)."
function push_start_args(left, right)
    T = term_type(left)
    return argPairs{T}(aWork{T}(left, right, 0, 0, 1), aWork{T}[])
end

# PORT: pl-variant.c push_args
"Push the current work and compare the arguments of `left` and `right` next (pl-variant.c)."
function push_args!(a::argPairs{T}, left::T, right::T, off::Int, arity::Int)::Bool where {T}
    push!(a.stack, a.work)
    a.work = aWork{T}(left, right, off, 0, arity)
    return true
end

# PORT: pl-variant.c next_arg as variant_next_arg
"The next pair of arguments, or `nothing` when the agenda is empty (pl-variant.c `next_arg`)."
function variant_next_arg!(a::argPairs{T})::Union{Nothing, Tuple{T, T}} where {T}
    while a.work.arg >= a.work.arity
        isempty(a.stack) && return nothing
        a.work = pop!(a.stack)
    end
    w = a.work
    a.work = aWork{T}(w.left, w.right, w.off, w.arg + 1, w.arity)
    if w.off == 0                       # the initial pair: the terms themselves
        return (w.left, w.right)
    end
    return (child(w.left, w.off + w.arg), child(w.right, w.off + w.arg))
end

"""
The functor test: two compounds match when they have the same functor — a symbol head with the
same name and the same arity — or, both `\$expr/n` (no symbol head, Q2), the same number of children
(their heads are then compared as arguments). `(off, arity)` of the left one, or `nothing`.
"""
function _variant_functor(l, r)::Union{Nothing, Tuple{Int, Int}}
    offl, arl = _comp_shape(l)
    offr, arr = _comp_shape(r)
    (offl == offr && arl == arr) || return nothing
    if offl == 2 && sym_key(child(l, 1)) != sym_key(child(r, 1))
        return nothing
    end
    return (offl, arl)
end

# PORT: pl-variant.c variant
# DIVERGES: atomic data are compared as `==` compares them (the standard order's chain in equality
# mode, `compare_std(…, CMP_MODE_EQUAL)` — the public `compareStandard` checks the term types once,
# at its entry, never per pair in a walk): SYM by `sym_key`, GND as the standard order's identity —
# upstream compares words and indirect data.
"""
Run the agenda: true when every pair matches under one consistent variable correspondence
(pl-variant.c).
"""
function variant(agenda::argPairs{T})::Bool where {T}
    left_to_right = Dict{UInt64, UInt64}()      # node->a: the right variable a left one maps to
    right_to_left = Dict{UInt64, UInt64}()      # node->b: the left variable a right one maps from
    while true
        pair = variant_next_arg!(agenda)
        pair === nothing && return true
        l, r = pair
        if kind(l) !== kind(r)
            return false
        end
        if kind(l) === VAR
            i = var_key(l)
            j = var_key(r)
            m = get(left_to_right, i, nothing)
            n = get(right_to_left, j, nothing)
            if m === nothing && n === nothing
                left_to_right[i] = j
                right_to_left[j] = i
                continue
            end
            if m !== nothing && n !== nothing
                if m == j && n == i
                    continue
                end
            end
            return false
        elseif kind(l) === SYM
            sym_key(l) == sym_key(r) || return false
        elseif kind(l) === GND
            compare_std(l, r, CMP_MODE_EQUAL) == CMP_EQUAL || return false
        else
            f = _variant_functor(l, r)
            f === nothing && return false
            push_args!(agenda, l, r, f[1], f[2])
        end
    end
end

# PORT: pl-variant.c is_variant_ptr
"""
    is_variant_ptr(t1, t2) -> Bool

`t1 =@= t2`: the terms are equal up to a one-to-one renaming of their variables (pl-variant.c).
"""
function is_variant_ptr(t1, t2)::Bool
    term_type(t1) === term_type(t2) || throw(
        ArgumentError(
            "is_variant_ptr: terms of two term types, $(term_type(t1)) and $(term_type(t2))"
        )
    )
    if t1 === t2                        # same term
        return true
    end
    if kind(t1) !== kind(t2)            # different type
        return false
    end
    k = kind(t1)                        # quick tests
    if k === VAR
        return true
    elseif k === SYM
        return sym_key(t1) == sym_key(t2)
    elseif k === GND
        return compare_std(t1, t2, CMP_MODE_EQUAL) == CMP_EQUAL     # the types checked above
    end
    if _variant_functor(t1, t2) === nothing
        return false
    end
    return variant(push_start_args(t1, t2))
end

# ── on the CELLS (L1d step 8a; the workspace's L1_plan/stageL1d_design.md §3i) ───────────────────
# Upstream numbers a node by OVERWRITING the cell that holds it after `deRef` — a variable cell with
# `consVar(n)`, a compound's cell with `consCompound_x(n)` — and `reset_terms` restores the cells. A
# numbered variable cell would be no `isVar` here and `_deref_loc` would read it through the value
# table, so the numbers live in a SIDE VECTOR by global position (`ld.vt_ids`, 0: unnumbered), cleared
# from the node buffer at the end: a representation-only DIVERGES, behaviour identical. A SLOT holding
# a compound's word is met only as the root (no global cell references a slot), so its node is never
# looked up again and is not recorded.

# ORIGINAL: the node number of global position `p` (0: unnumbered).
@inline _vt_id(ld::PL_local_data, p::Int)::Int =
    p <= length(ld.vt_ids) ? Int(ld.vt_ids[p]) : 0

# ORIGINAL: record node `n` for global position `p`, growing the side vector (new entries 0).
function _vt_id!(ld::PL_local_data, p::Int, n::Int)::Nothing
    s = ld.vt_ids
    m = length(s)
    if p > m
        resize!(s, max(p, 2 * m, 64))
        fill!(view(s, (m + 1):length(s)), Int32(0))
    end
    s[p] = Int32(n)
    return nothing
end

# PORT: pl-variant.c term_id as vt_node_id
# DIVERGES: one function for `term_id` and `var_id` (the side vector holds either kind's number); `loc` the dereferenced
# location, `w` its word; a slot's node is not recorded (see the section header).
"The node number of the cell at location `loc` holding word `w`, numbering it if new (pl-variant.c `var_id`/`term_id`)."
function vt_node_id(ld::PL_local_data, loc::Int, w::word)::Int
    loc > 0 && (n = _vt_id(ld, loc)) != 0 && return n
    push!(ld.vt_nodes, vt_node(loc, w, 0, 0))
    n = length(ld.vt_nodes)
    loc > 0 && _vt_id!(ld, loc, n)
    return n
end

# PORT: pl-variant.c Root as vt_root
"The root of node `i`'s class of isomorphic compounds (pl-variant.c `Root`)."
function vt_root(ld::PL_local_data, i::Int)::Int
    while true
        k = i
        i = ld.vt_nodes[i].b                    # node_isom(n)
        i == 0 && return k
    end
end

# PORT: pl-variant.c push_args as vt_push_args!
"Push the current work and walk the `arity` argument pairs from `left`, `right` next (pl-variant.c)."
function vt_push_args!(a::vt_pairs, left::Int, right::Int, arity::Int)::Nothing
    push!(a.stack, (a.left, a.right, a.arg, a.arity))
    a.left, a.right, a.arg, a.arity = left, right, 0, arity     # push_start_args
    return nothing
end

# PORT: pl-variant.c next_arg as vt_next_arg!
"The next argument pair `(found, l, r)` (pl-variant.c `next_arg`); `l == 0` is `isomorphic`'s sentinel."
function vt_next_arg!(a::vt_pairs)::Tuple{Bool, Int, Int}
    while a.arg >= a.arity
        isempty(a.stack) && return (false, 0, 0)
        a.left, a.right, a.arg, a.arity = pop!(a.stack)
    end
    l, r = a.left, a.right
    a.arg += 1
    if l != 0                                   # the initial dummy node has NULL
        a.left += 1
        a.right += 1
    end
    return (true, l, r)
end

# ORIGINAL: the deRef'd location's word and its node location — upstream's `deRef(l); wl = *l`: the
# global position holding the word, or the slot `loc` itself for a word in a slot.
@inline _vt_loc(loc::Int, p::Int)::Int = p > 0 ? p : loc

# ORIGINAL: the atomic case of `variant`/`isomorphic` — `wl == wr`, an atom, an inline integer,
# `equalIndirect` — as the standard order's equality on cells (SWI's identity: `1` and `1.0` differ).
@inline _vt_same_atomic(
    ld::PL_local_data, k1::UInt8, w1::word, p1::Int, k2::UInt8, w2::word, p2::Int
)::Bool =
    compare_primitives_cells(ld, k1, w1, p1, k2, w2, p2, CMP_MODE_EQUAL) == CMP_EQUAL

# PORT: pl-variant.c isomorphic as isomorphic_cells
# DIVERGES: on locations. As upstream it pushes a sentinel onto the CALLER's agenda and runs until it
# pops it. An attributed variable (AV3) is compared by its attribute list (`goto attvar`), as upstream.
"Whether compound nodes `i` and `j` are `==` (pl-variant.c `isomorphic`): 1 or 0."
function isomorphic_cells(ld::PL_local_data, a::vt_pairs, i::Int, j::Int)::Int
    i == j && return 1
    vt_push_args!(a, 0, 0, 1)                   # push_args(a, dummy, dummy, 1)
    lm = valPtr(ld.vt_nodes[i].orig)            # univ(node_orig(Node(i, buf)), &dm, &lm)
    ln = valPtr(ld.vt_nodes[j].orig)
    dm, dn = ld.gstack[lm], ld.gstack[ln]
    dm != dn && return 0
    vt_push_args!(a, lm + 1, ln + 1, arityFunctor(ld.functors, dm))
    while true
        found, l, r = vt_next_arg!(a)
        found || return 1
        l == 0 && return 1
        @label attvar
        k1, w1, p1 = _deref_loc(ld, l)
        k2, w2, p2 = _deref_loc(ld, r)
        c1, c2 = k1 == DU_WORD && _is_gcompound(w1), k2 == DU_WORD && _is_gcompound(w2)
        if k1 == DU_CELL || k2 == DU_CELL       # tag(wl) != tag(wr); TAG_VAR
            (k1 == k2 && p1 == p2) || return 0  # identity test on variables
            continue
        end
        if k1 == DU_ATTVAR || k2 == DU_ATTVAR   # tag(wl) != tag(wr); TAG_ATTVAR (AV3)
            k1 == k2 || return 0
            l, r = valPtr(w1), valPtr(w2)       # l = valPAttVar(wl); r = valPAttVar(wr)
            @goto attvar
        end
        c1 == c2 || return 0                    # tag(wl) != tag(wr)
        if !c1
            _vt_same_atomic(ld, k1, w1, p1, k2, w2, p2) || return 0
            continue
        end
        ii = vt_root(ld, vt_node_id(ld, _vt_loc(l, p1), w1))    # number both before looking
        jj = vt_root(ld, vt_node_id(ld, _vt_loc(r, p2), w2))    # either up
        ii == jj && continue
        lm, ln = valPtr(ld.vt_nodes[ii].orig), valPtr(ld.vt_nodes[jj].orig)
        dm, dn = ld.gstack[lm], ld.gstack[ln]
        dm != dn && return 0
        if ii <= jj                             # union
            m = ld.vt_nodes[ii]
            ld.vt_nodes[ii] = vt_node(m.bp, m.orig, m.a, jj)
        else
            n = ld.vt_nodes[jj]
            ld.vt_nodes[jj] = vt_node(n.bp, n.orig, n.a, ii)
        end
        vt_push_args!(a, lm + 1, ln + 1, arityFunctor(ld.functors, dm))
    end
end

# PORT: pl-variant.c variant as variant_cells
# DIVERGES: on locations; no MEMORY_OVERFLOW. An attributed variable (AV3) is a variable whose
# attribute lists are then compared (`goto attvar`), as upstream.
"Run the agenda (pl-variant.c `variant`): 1 when every pair matches under one variable correspondence, else 0."
function variant_cells(ld::PL_local_data, a::vt_pairs)::Int
    while true
        found, l, r = vt_next_arg!(a)
        found || return 1
        @label attvar
        k1, w1, p1 = _deref_loc(ld, l)
        k2, w2, p2 = _deref_loc(ld, r)
        if k1 == DU_CELL || k2 == DU_CELL || k1 == DU_ATTVAR || k2 == DU_ATTVAR   # needsRef(wl)
            k1 == k2 || return 0                # tag(wl) != tag(wr)
            av = k1 == DU_ATTVAR                # al = valPAttVar(wl), ar = valPAttVar(wr) (AV3)
            i = vt_node_id(ld, p1, word(0))
            j = vt_node_id(ld, p2, word(0))
            vl = ld.vt_nodes[i]
            m = vl.a
            n = ld.vt_nodes[j].b
            if m == 0 && n == 0
                ld.vt_nodes[i] = vt_node(vl.bp, vl.orig, j, vl.b)
                vr = ld.vt_nodes[j]             # (i == j: the node just written)
                ld.vt_nodes[j] = vt_node(vr.bp, vr.orig, vr.a, i)
                if av                           # if ( al ) { l = al; r = ar; goto attvar; }
                    l, r = valPtr(w1), valPtr(w2)
                    @goto attvar
                end
                continue
            end
            if m != 0 && n != 0 && m == j && n == i
                if av                           # if ( al ) { l = al; r = ar; goto attvar; }
                    l, r = valPtr(w1), valPtr(w2)
                    @goto attvar
                end
                continue
            end
            return 0
        end
        c1, c2 = k1 == DU_WORD && _is_gcompound(w1), k2 == DU_WORD && _is_gcompound(w2)
        c1 == c2 || return 0                    # tag(wl) != tag(wr)
        if !c1
            _vt_same_atomic(ld, k1, w1, p1, k2, w2, p2) || return 0
            continue
        end
        i = vt_node_id(ld, _vt_loc(l, p1), w1)
        j = vt_node_id(ld, _vt_loc(r, p2), w2)
        mnode = ld.vt_nodes[i]
        kk = mnode.a                            # node_variant(m)
        if kk != 0
            h = isomorphic_cells(ld, a, kk, j)
            h == 1 || return h
            continue
        end
        lm, ln = valPtr(mnode.orig), valPtr(ld.vt_nodes[j].orig)    # univ
        dm, dn = ld.gstack[lm], ld.gstack[ln]
        dm != dn && return 0
        ld.vt_nodes[i] = vt_node(mnode.bp, mnode.orig, j, mnode.b)  # node_variant(m) = j
        vt_push_args!(a, lm + 1, ln + 1, arityFunctor(ld.functors, dm))
    end
end

# PORT: pl-variant.c is_variant_ptr as is_variant_ptr_cells
# DIVERGES: on locations; no ERR_NOMEM. Two attributed variables (AV3): their attribute lists, as
# upstream's `goto again` — a list that is not a compound (`[]`) answers false, as its TAG_ATOM case.
"""
    is_variant_ptr_cells(ld, l1, l2) -> Bool

The terms at locations `l1`, `l2` are variants (`=@=`, pl-variant.c `is_variant_ptr`), rational
trees included.
"""
function is_variant_ptr_cells(ld::PL_local_data{T}, l1::Int, l2::Int)::Bool where {T}
    k1, w1, p1 = _deref_loc(ld, l1)
    k2, w2, p2 = _deref_loc(ld, l2)
    k1 == DU_CELL && k2 == DU_CELL && return true   # *p1 == *p2; TAG_VAR
    k1 == k2 && w1 == w2 && k1 != DU_CELL && return true    # same term
    (k1 == DU_CELL || k2 == DU_CELL) && return false        # different type
    (k1 == DU_ATTVAR) == (k2 == DU_ATTVAR) || return false  # different type (AV3)
    if k1 == DU_ATTVAR                                      # TAG_ATTVAR (AV3)
        while k1 == DU_ATTVAR && k2 == DU_ATTVAR            # p = valPAttVar(*p); goto again
            l1, l2 = valPtr(w1), valPtr(w2)
            k1, w1, p1 = _deref_loc(ld, l1)
            k2, w2, p2 = _deref_loc(ld, l2)
        end
        k1 == DU_CELL && return true                        # TAG_VAR
        (k1 == DU_WORD && _is_gcompound(w1) && k2 == DU_WORD && _is_gcompound(w2)) ||
            return false                                    # TAG_ATOM: `[]`
    end
    c1, c2 = k1 == DU_WORD && _is_gcompound(w1), k2 == DU_WORD && _is_gcompound(w2)
    c1 == c2 || return false
    c1 || return _vt_same_atomic(ld, k1, w1, p1, k2, w2, p2)    # quick tests
    ld.gstack[valPtr(w1)] == ld.gstack[valPtr(w2)] || return false   # t1->definition
    a = ld.vt_agenda
    @assert isempty(ld.vt_nodes) && isempty(a.stack)
    a.left, a.right, a.arg, a.arity = _vt_loc(l1, p1), _vt_loc(l2, p2), 0, 1   # push_start_args
    rval = variant_cells(ld, a)
    for r in ld.vt_nodes                        # reset_terms
        r.bp > 0 && (ld.vt_ids[r.bp] = Int32(0))
    end
    empty!(ld.vt_nodes)
    empty!(a.stack)
    return rval == 1
end


# ── the built-in (V5a2, decision 5) ──────────────────────────────────────────────────────────────
# PORT: pl-variant.c variant as pl_variant2_va
# (PRED_IMPL("=@=", 2, variant, 0)) — upstream's one line; its ERR_NOMEM is `is_variant_ptr`'s
"`=@=/2` (pl-variant.c): the arguments are variants, under the bindings."
function pl_variant2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    return is_variant_ptr_cells(ld, -(A1 + 1), -(A2 + 1)) ? FTRUE : FFALSE    # valTermRef (L1d 8a)
end

# PORT: pl-variant.c BeginPredDefs as PL_predicates_from_variant
# DIVERGES: the ported entry only (upstream's table also has `\=@=`, var:544-546).
"pl-variant.c's registration table (`BeginPredDefs(variant)`): the ported entry."
const PL_predicates_from_variant = (PL_extension("=@=", 2, pl_variant2_va, PL_FA_VARARGS),)
