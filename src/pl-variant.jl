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
# DIVERGES (file-wide): upstream numbers COMPOUND cells too (`term_id`, `Root`, `isomorphic`,
# `univ`, `reset_terms`), marking them in place, so that cyclic terms terminate and a compound met
# twice is compared by identity of its partner. Interface terms are finite trees and have no cells
# to mark, so those functions are not ported and every compound is walked: for a finite term with
# shared subterms the answer is the same (a shared left subterm met again maps its variables
# through the same correspondence, which fails exactly when upstream's `isomorphic` does).
# Variables are found by `var_key` in two maps where upstream overwrites the variable's cell.

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
