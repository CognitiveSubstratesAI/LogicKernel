# UPSTREAM: swipl-devel src/pl-variant.c @ 8e1bc1110be4
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2016, Kuniaki Mukai
#
# VARIANT CHECKING — `=@=`: two terms are variants when they are equal up to a consistent,
# one-to-one renaming of their variables. SWI-Prolog's pl-variant.c, ported: the same argument
# agenda (`argPairs`, `push_args`, `next_arg`), the same two-way variable correspondence (a left
# variable maps to exactly one right variable and back — upstream's node fields `a` and `b`), the
# same quick tests in `is_variant_ptr`.
#
# TWO ENTRIES. Without `ld`, for RESOLVED terms: DIVERGES — upstream numbers COMPOUND cells too
# (`term_id`, `Root`, `isomorphic`), so that cyclic terms terminate and a compound met twice is
# compared by identity of its partner; a resolved term is a finite tree, so this entry walks every
# compound instead — for a finite term with shared subterms the answer is the same (a shared left
# subterm met again maps its variables through the same correspondence, which fails exactly when
# upstream's `isomorphic` does); variables are found by `var_key` in two maps where upstream
# overwrites the variable's cell. With `ld` (V5a, at the end of the file), under bindings, where a
# term can be a rational tree: upstream's numbering is ported (`node`, `var_id`, `term_id`, `Root`,
# `isomorphic`), over identity maps instead of overwritten cells.

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

# ── =@= UNDER BINDINGS (V5a) ─────────────────────────────────────────────────────────────────────
# Upstream's `is_variant_ptr` takes `DECL_LD` and dereferences every pair (var:461-462, 351-352): a
# built-in reads its arguments from slots whose variables may be bound, and through bindings a term
# can be a rational tree. So these methods port upstream's NUMBERING of compounds too — `term_id`,
# `Root`, the union of isomorphic nodes in `isomorphic` — which is what makes a cyclic term
# terminate (the same compound comes round again). The methods above, without `ld`, stay the entry
# for RESOLVED terms, finite trees, where every compound may simply be walked.

# PORT: pl-variant.c node
# DIVERGES: `bp` and `orig` (the cell and the word saved to restore it) are the term itself — no
# cell is overwritten (see `variant_buffer`); `0` is a link not set, as upstream's dummy node 0.
"A variable or a compound the walk has numbered (pl-variant.c `struct node`)."
struct node{T}
    orig::T             # the term (upstream: the saved word of the cell `bp`)
    a::Int              # variant at left (node_variant for a compound)
    b::Int              # link to isomorphic node (node_isom)
end

# PORT: pl-variant.c VARIANT_BUFFER as variant_buffer
# DIVERGES: upstream numbers a node by OVERWRITING its cell (`consVar(n)`, `consCompound_x(n)`) and
# restores the cells afterwards (`reset_terms`). Here the numbers are entries in two maps — a
# variable by `var_key`, a compound by IDENTITY (`IdDict`) — dropped with the buffer, and node `i`
# is `nodes[i]`, from 1. Upstream numbers the CELL that holds a compound; here the compound object.
# The answer is the same: a compound object reached twice is one shared subterm (upstream: two
# cells of the same compound, whose nodes `isomorphic` then unites at once — the same functor and
# the same arguments), and a cycle, which passes through a binding, returns to the same object.
"The numbered variables and compounds of one `=@=` walk (pl-variant.c's node buffer)."
struct variant_buffer{T}
    nodes::Vector{node{T}}
    vars::Dict{UInt64, Int}
    terms::IdDict{T, Int}
end
variant_buffer{T}() where {T} =
    variant_buffer{T}(node{T}[], Dict{UInt64, Int}(), IdDict{T, Int}())

# PORT: pl-variant.c var_id
"The node number of variable `v`, numbering it if new (pl-variant.c `var_id`)."
function var_id(buf::variant_buffer{T}, v::T)::Int where {T}
    return get!(buf.vars, var_key(v)) do
        push!(buf.nodes, node{T}(v, 0, 0))
        length(buf.nodes)
    end
end

# PORT: pl-variant.c term_id
"The node number of compound `t`, numbering it if new (pl-variant.c `term_id`)."
function term_id(buf::variant_buffer{T}, t::T)::Int where {T}
    return get!(buf.terms, t) do
        push!(buf.nodes, node{T}(t, 0, 0))
        length(buf.nodes)
    end
end

# PORT: pl-variant.c Root
"The root of node `i`'s class of isomorphic compounds (pl-variant.c `Root`)."
function Root(buf::variant_buffer{T}, i::Int)::Int where {T}
    while true
        k = i
        i = buf.nodes[i].b                      # node_isom(n)
        i == 0 && return k
    end
end

"Atomic `l` and `r` of one kind are the same: SYM by `sym_key`, GND in the standard order's identity."
_variant_same_atomic(l, r)::Bool =
    if kind(l) === SYM
        sym_key(l) == sym_key(r)
    else
        compare_std(l, r, CMP_MODE_EQUAL) == CMP_EQUAL
    end

# PORT: pl-variant.c isomorphic
# DIVERGES: walks its own agenda where upstream pushes a sentinel (NULL) onto the caller's and runs
# until it pops it — the same pairs in the same order. No attributed variables.
"""
    isomorphic(ld, buf, i, j) -> Bool

Whether compound nodes `i` and `j` are the SAME term up to structure — variables by identity, the
compounds met on the way united as isomorphic (pl-variant.c `isomorphic`, `==` on rational trees).
"""
function isomorphic(
    ld::PL_local_data{T}, buf::variant_buffer{T}, i::Int, j::Int
)::Bool where {T}
    i == j && return true
    lm = buf.nodes[i].orig                      # univ(node_orig(Node(i, buf)), &dm, &lm)
    ln = buf.nodes[j].orig
    f = _variant_functor(lm, ln)
    f === nothing && return false               # dm != dn
    a = argPairs{T}(aWork{T}(lm, ln, f[1], 0, f[2]), aWork{T}[])
    while true
        pair = variant_next_arg!(a)
        pair === nothing && return true
        l = deRef(ld, pair[1])
        r = deRef(ld, pair[2])
        kind(l) === kind(r) || return false     # tag(wl) != tag(wr)
        k = kind(l)
        if k === VAR
            var_key(l) == var_key(r) || return false    # identity test on variables
            continue
        elseif k !== EXPR
            _variant_same_atomic(l, r) || return false
            continue
        end
        ii = Root(buf, term_id(buf, l))         # number both before looking either up
        jj = Root(buf, term_id(buf, r))
        ii == jj && continue
        m = buf.nodes[ii]
        n = buf.nodes[jj]
        g = _variant_functor(m.orig, n.orig)
        g === nothing && return false
        if ii <= jj                             # union
            buf.nodes[ii] = node{T}(m.orig, m.a, jj)
        else
            buf.nodes[jj] = node{T}(n.orig, n.a, ii)
        end
        push_args!(a, m.orig, n.orig, g[1], g[2])
    end
end

# PORT: pl-variant.c variant
# DIVERGES: no attributed variables; no MEMORY_OVERFLOW.
"""
    variant(ld, agenda, buf) -> Bool

Run the agenda under the bindings in `ld` (pl-variant.c `variant`): true when every pair matches
under one consistent variable correspondence, numbering variables and compounds as it goes.
"""
function variant(
    ld::PL_local_data{T}, agenda::argPairs{T}, buf::variant_buffer{T}
)::Bool where {T}
    while true
        pair = variant_next_arg!(agenda)
        pair === nothing && return true
        l = deRef(ld, pair[1])
        r = deRef(ld, pair[2])
        kind(l) === kind(r) || return false     # tag(wl) != tag(wr)
        k = kind(l)
        if k === VAR                            # needsRef(wl)
            i = var_id(buf, l)
            j = var_id(buf, r)
            vl = buf.nodes[i]
            m = vl.a
            n = buf.nodes[j].b
            if m == 0 && n == 0
                buf.nodes[i] = node{T}(vl.orig, j, vl.b)
                vr = buf.nodes[j]               # (i == j: the node just written)
                buf.nodes[j] = node{T}(vr.orig, vr.a, i)
                continue
            end
            if m != 0 && n != 0 && m == j && n == i
                continue
            end
            return false
        elseif k !== EXPR
            _variant_same_atomic(l, r) || return false
            continue
        end
        i = term_id(buf, l)
        j = term_id(buf, r)
        mnode = buf.nodes[i]
        kk = mnode.a                            # node_variant(m)
        if kk != 0
            isomorphic(ld, buf, kk, j) || return false
            continue
        end
        f = _variant_functor(l, r)              # univ: dm != dn
        f === nothing && return false
        buf.nodes[i] = node{T}(mnode.orig, j, mnode.b)  # node_variant(m) = j
        push_args!(agenda, l, r, f[1], f[2])
    end
end

# PORT: pl-variant.c is_variant_ptr
# DIVERGES: no attributed variables; no ERR_NOMEM (no MEMORY_OVERFLOW).
"""
    is_variant_ptr(ld, t1, t2) -> Bool

`t1 =@= t2` under the bindings in `ld` (pl-variant.c `is_variant_ptr`) — rational trees included.
"""
function is_variant_ptr(ld::PL_local_data{T}, t1::T, t2::T)::Bool where {T}
    p1 = deRef(ld, t1)
    p2 = deRef(ld, t2)
    p1 === p2 && return true                    # same term
    kind(p1) === kind(p2) || return false       # different type
    k = kind(p1)                                # quick tests
    if k === VAR
        return true
    elseif k !== EXPR
        return _variant_same_atomic(p1, p2)
    end
    _variant_functor(p1, p2) === nothing && return false
    return variant(ld, push_start_args(p1, p2), variant_buffer{T}())
end

# ── on the CELLS (L1d step 8a; the workspace's L1_plan/stageL1d_design.md §3i) ───────────────────
# Upstream numbers a node by OVERWRITING the cell that holds it after `deRef` — a variable cell with
# `consVar(n)`, a compound's cell with `consCompound_x(n)` — and `reset_terms` restores the cells. A
# numbered variable cell would be no `isVar` here and `_deref_loc` would read it through the value
# table, so the numbers live in a SIDE VECTOR by global position (`ld.vt_ids`, 0: unnumbered), cleared
# from the node buffer at the end: a representation-only DIVERGES, behaviour identical. A SLOT holding
# a compound's word is met only as the root (no global cell references a slot), so its node is never
# looked up again and is not recorded. The BOUNDARY (`DU_TERM`: a keyed variable's binding, a slot's
# side value) aborts the walk; the whole check is redone on terms above, counted in `cold_pairs`.
# TRANSITIONAL until L1f.
"`variant_cells`: the walk met the boundary."
const VT_BOUNDARY = -1

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
# DIVERGES: on locations; returns `VT_BOUNDARY` at the boundary; no attributed variables. As upstream it
# pushes a sentinel onto the CALLER's agenda and runs until it pops it.
"Whether compound nodes `i` and `j` are `==` (pl-variant.c `isomorphic`): 1, 0, or `VT_BOUNDARY`."
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
        k1, w1, p1 = _deref_loc(ld, l)
        k2, w2, p2 = _deref_loc(ld, r)
        (k1 == DU_TERM || k2 == DU_TERM) && return VT_BOUNDARY
        c1, c2 = k1 == DU_WORD && _is_gcompound(w1), k2 == DU_WORD && _is_gcompound(w2)
        if k1 == DU_CELL || k2 == DU_CELL       # tag(wl) != tag(wr); TAG_VAR
            (k1 == k2 && p1 == p2) || return 0  # identity test on variables
            continue
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
# DIVERGES: on locations; returns `VT_BOUNDARY` at the boundary; no attributed variables; no
# MEMORY_OVERFLOW.
"Run the agenda (pl-variant.c `variant`): 1 when every pair matches under one variable correspondence, 0, or `VT_BOUNDARY`."
function variant_cells(ld::PL_local_data, a::vt_pairs)::Int
    while true
        found, l, r = vt_next_arg!(a)
        found || return 1
        k1, w1, p1 = _deref_loc(ld, l)
        k2, w2, p2 = _deref_loc(ld, r)
        (k1 == DU_TERM || k2 == DU_TERM) && return VT_BOUNDARY
        if k1 == DU_CELL || k2 == DU_CELL       # needsRef(wl)
            k1 == k2 || return 0                # tag(wl) != tag(wr)
            i = vt_node_id(ld, p1, word(0))
            j = vt_node_id(ld, p2, word(0))
            vl = ld.vt_nodes[i]
            m = vl.a
            n = ld.vt_nodes[j].b
            if m == 0 && n == 0
                ld.vt_nodes[i] = vt_node(vl.bp, vl.orig, j, vl.b)
                vr = ld.vt_nodes[j]             # (i == j: the node just written)
                ld.vt_nodes[j] = vt_node(vr.bp, vr.orig, vr.a, i)
                continue
            end
            m != 0 && n != 0 && m == j && n == i && continue
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
# DIVERGES: on locations; at the boundary the check is redone on terms (`is_variant_ptr(ld, …)`,
# counted in `cold_pairs`); no attributed variables; no ERR_NOMEM.
"""
    is_variant_ptr_cells(ld, l1, l2) -> Bool

The terms at locations `l1`, `l2` are variants (`=@=`, pl-variant.c `is_variant_ptr`), rational
trees included.
"""
function is_variant_ptr_cells(ld::PL_local_data{T}, l1::Int, l2::Int)::Bool where {T}
    k1, w1, p1 = _deref_loc(ld, l1)
    k2, w2, p2 = _deref_loc(ld, l2)
    (k1 == DU_TERM || k2 == DU_TERM) && return _vt_on_terms(ld, k1, w1, p1, k2, w2, p2)
    k1 == DU_CELL && k2 == DU_CELL && return true   # *p1 == *p2; TAG_VAR
    k1 == k2 && w1 == w2 && k1 != DU_CELL && return true    # same term
    (k1 == DU_CELL || k2 == DU_CELL) && return false        # different type
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
    rval == VT_BOUNDARY && return _vt_on_terms(ld, k1, w1, p1, k2, w2, p2)
    return rval == 1
end

# ORIGINAL: the boundary — the whole check on terms (TRANSITIONAL until L1f), counted.
@noinline function _vt_on_terms(
    ld::PL_local_data{T}, k1::UInt8, w1::word, p1::Int, k2::UInt8, w2::word, p2::Int
)::Bool where {T}
    ld.cold_pairs += 1
    return is_variant_ptr(ld, _loc_term(ld, k1, w1, p1), _loc_term(ld, k2, w2, p2))
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
