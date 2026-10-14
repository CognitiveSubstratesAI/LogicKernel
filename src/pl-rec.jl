# UPSTREAM: swipl-devel src/pl-rec.c @ 8609e216cab9
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# RECORDED TERMS (pl-rec.c), exactly these: `compileTermToHeap` — a term taken off the stacks, so
# that it survives backtracking — and `copyRecordToGlobal` — the term put back, its variables
# fresh. Their first caller is findall/3 (src/pl-bag.jl): an answer is recorded, the goal is
# backtracked into, and the answers are put back when it has no more.
#
# WHAT UPSTREAM DOES. `compile_term_to_heap` writes the term as a byte code into a buffer — a
# variable as its number among the term's variables, an atom as its handle, a cyclic reference as
# `PL_REC_CYCLE` and the offset of the compound it points back to — and `copy_record` reads the
# code back onto the global stack.
#
# WHAT THE KERNEL DOES INSTEAD (decision 2). A term is an immutable value, which backtracking
# cannot touch: the record is the term itself (`record`, src/pl-incl.jl), with every bound variable
# replaced by its value and its variables renamed to keys of the record's own — `copy_term`'s walk
# (src/pl-copyterm.jl), whose cyclic copies are kept in the record instead of in the binding store.
# Putting it back renames the variables again, to fresh ones, and binds the cyclic copies.
#
# THE ORDER OF THE FRESH VARIABLES is upstream's: `copy_record` lays a compound's cells out when it
# meets the compound — compounds in depth-first order — and a variable lives in the lowest of the
# argument cells that hold it, so the standard order of two fresh variables is the order of those
# cells. `_rec_copy` gives a compound's own variable arguments their fresh keys when it starts the
# compound, before its compound arguments: the same order.
#
# NOT PORTED: the rest of pl-rec.c — the recorded database (`recorda/3`, `recorded/3`, `erase/1`,
# `instance/2`, the keys and their lists), external records (`PL_record_external`), `PL_record`,
# `PL_duplicate_record`, `variantRecords`, `term_complexity`, atom references and their marking
# (`markAtomsRecord`: no atom GC), attributed variables (`PL_REC_ALLOCVAR`), and `freeRecord` (a
# record is freed by Julia's GC).

# PORT: pl-rec.c compileTermToHeap_ex as compileTermToHeap
# DIVERGES: see the file header — the record is the term's copy (`copy_term`, ground subterms
# shared: a value cannot change), and the bindings its cyclic copies made are taken off the trail
# into the record. An atomic or ground term is its own record. NOT PORTED: `allocate` and `ctx`
# (the caller's allocator) and `flags` (`R_NOLOCK`, `R_DUPLICATE`, `R_EXTERNAL`: atom references,
# duplicated and external records).
"""
    compileTermToHeap(ld, t) -> record

Record the term `t` references (pl-rec.c): a copy that no longer needs the bindings of `ld`, and
that undoing them does not change.
"""
function compileTermToHeap(ld::PL_local_data{T}, t::term_t)::record{T} where {T}
    p = deRef(ld, ld.slots[t + 1])
    k = kind(p)
    if k !== VAR && (k !== EXPR || is_ground(p))
        return record{T}(p, nothing, true)
    end
    m = Mark(ld)
    ld.mark_bar = NO_MARK_BAR       # the harvest below reads the copy's bindings off the trail
    c = copy_term(ld, p, cp_options(true))
    if length(ld.trail) == m.trailtop
        DiscardMark(ld, m)
        return record{T}(c, nothing, false)
    end
    cycles = Tuple{UInt64, T}[]                     # the cyclic copies: w = r, and r holds w
    for i in (m.trailtop + 1):length(ld.trail)
        key = ld.trail[i]
        push!(cycles, (key, deRef(ld, mk_var(T, key))))
    end
    Undo!(ld, m)
    DiscardMark(ld, m)
    return record{T}(c, cycles, false)
end

# The fresh variable of the record's variable `key`, made when first asked for.
function _rec_var(ld::PL_local_data{T}, vars::Dict{UInt64, T}, key::UInt64)::T where {T}
    w = get(vars, key, nothing)
    w === nothing || return w
    v = mk_var(T, allocGlobalVars!(ld, 1))
    vars[key] = v
    return v
end

# Give the variable arguments of compound `t` their fresh variables, in argument order.
function _rec_block!(ld::PL_local_data{T}, vars::Dict{UInt64, T}, t::T)::Nothing where {T}
    for i in 1:nchildren(t)
        c = child(t, i)
        kind(c) === VAR && _rec_var(ld, vars, var_key(c))
    end
    return nothing
end

# PORT: pl-rec.c copy_record as _rec_copy
# DIVERGES: see the file header — the term is rebuilt with its variables renamed by `vars`; the
# walk is upstream's (a compound's cells are made when it is met, its arguments then in order),
# with an explicit stack for the term agenda. A ground subterm is shared, not rebuilt.
"The record's term `t` with its variables renamed by `vars`, fresh ones made as they are met."
function _rec_copy(ld::PL_local_data{T}, vars::Dict{UInt64, T}, t::T)::T where {T}
    k = kind(t)
    k === VAR && return _rec_var(ld, vars, var_key(t))
    (k !== EXPR || is_ground(t)) && return t
    _rec_block!(ld, vars, t)
    stack = Tuple{T, Vector{T}}[(t, T[])]           # (compound, its arguments copied so far)
    while true
        node, kids = stack[end]
        i = length(kids) + 1
        if i > nchildren(node)
            pop!(stack)
            r = mk_expr(T, kids)
            isempty(stack) && return r
            push!(stack[end][2], r)
            continue
        end
        c = child(node, i)
        kc = kind(c)
        if kc === VAR
            push!(kids, _rec_var(ld, vars, var_key(c)))
        elseif kc === EXPR && !is_ground(c)
            _rec_block!(ld, vars, c)
            push!(stack, (c, T[]))
        else
            push!(kids, c)
        end
    end
end

# PORT: pl-rec.c copyRecordToGlobal
# DIVERGES: see the file header — no global stack, so nothing to allocate and no `flags`
# (`ALLOW_GC`); a cyclic reference is a fresh variable bound (trailed) to the copy of its
# compound, as `copy_term`'s (src/pl-copyterm.jl). Always true (upstream: false when out of stack).
"""
    copyRecordToGlobal(ld, copy, r) -> Bool

Make term reference `copy` hold the term of record `r`, its variables fresh (pl-rec.c).
"""
function copyRecordToGlobal(
    ld::PL_local_data{T}, copy::term_t, r::record{T}
)::Bool where {T}
    if r.ground
        ld.slots[copy + 1] = r.term
        return true
    end
    vars = Dict{UInt64, T}()
    ld.slots[copy + 1] = _rec_copy(ld, vars, r.term)
    cycles = r.cycles
    if cycles !== nothing
        for (key, v) in cycles
            w = _rec_var(ld, vars, key)
            Trail!(ld, var_key(w), _rec_copy(ld, vars, v))
        end
    end
    return true
end
