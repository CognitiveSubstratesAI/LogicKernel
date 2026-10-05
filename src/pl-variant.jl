# UPSTREAM: swipl-devel src/pl-variant.c @ bae881a24a3f
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
