# UPSTREAM: swipl-devel src/pl-copyterm.c @ 8e1bc1110be4
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2026, University of Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# COPYING TERMS — SWI-Prolog's `copy_term/2`, `copy_term_nat/2` and `duplicate_term/2`, the
# attribute-free path only.
#
# WHAT UPSTREAM DOES. A term is copied with its variables renamed consistently — a variable met twice
# becomes one fresh variable met twice — and, under `COPY_SHARE` (`copy_term/2`), a GROUND subterm is
# not copied but shared with the original; `duplicate_term/2` copies every compound. Upstream uses the
# GC mark bits of the global stack to classify each cell (virgin, visited, shared, ground) in a
# marking pass (`mark_for_copy`, `mark_for_duplicate`), then copies (`copy_term`), then clears the
# marks (`cp_unmark`); cyclic terms are copied by `initCyclicCopy`'s link table.
#
# WHAT THE KERNEL DOES INSTEAD. A term is an immutable value and a variable a keyed value, so there
# are no cells to mark and nothing to unmark: ONE bottom-up walk with an explicit work stack builds
# the copy. A compound is SHARED when every child of it is its own copy (an atomic, or a compound
# shared in turn: `===`) — a compound with a variable below, bound or not, is rebuilt, as upstream's
# is (a ground term is `is_ground`; a term with a bound variable has a cell that is a reference).
# A CYCLIC term exists only through the binding store (a variable bound to a term that holds it), so
# the walk follows a bound variable once and meets it again as an `in progress` mark: the copy is then
# a FRESH variable bound (trailed) to the copy of the term — a cyclic copy, as upstream's.
#
# CELL IDENTITY (the marker is at `copy_term`): the copy keeps the TERM, not the identity of its
# cells. Upstream marks cells, so a compound met twice is copied once; the walk here knows a
# compound again only by the bound variable it was reached through. A compound met both directly
# and through its variable is copied twice — and where that is the entry of a cycle (`f(C)`,
# `C = [a|X]`, `X` bound to `C`) the copy is the cycle unrolled by one compound: `[a|R]` with
# `R = [a|R]`. Every answer is the same (`==`, `=@=`, unification, writing); `same_term/2` and the
# factorising of a cyclic term would tell, and the kernel has neither. It goes with the term layout
# (step L1), where a copy is of cells.
#
# NOT PORTED: attributed variables (`COPY_ATTRS`, `must_copy_attvar`, `unshare_attvar`: no attributed
# variables), `copy_term/4`, `copy_term_nat/4` (`COPY_MARKED`, `mark_vars`), `size_abstract_term/3`
# (`COPY_ABSTRACT`), `duplicate_term`'s `nshare`/`share` (the shared subterms of `duplicate_term/2`
# are none: `nshare` is 0) and the fast heap terms (`$fast_record`, `term_to_fastheap`).

# PORT: pl-copyterm.c cp_options
"The options of a copy (pl-copyterm.c `cp_options`): the kernel's is the sharing of ground terms (`COPY_SHARE`)."
struct cp_options
    share::Bool
end

# One compound being copied: the original, the copies of its children so far (children 1…n, the
# head first), the index of the next child, whether every child so far is its own copy, and the
# keys of the bound variables the walk went through to reach it (their copies are this one's).
mutable struct _cp_frame{T}
    orig::T
    kids::Vector{T}
    next::Int
    same::Bool
    chain::Vector{UInt64}
end

# The state of one copy.
mutable struct _cp_state{T}
    share::Bool
    vars::Dict{UInt64, T}               # an unbound variable → its fresh variable
    done::Dict{UInt64, T}               # a bound variable → the copy of the term it is bound to
    inprogress::Set{UInt64}             # bound variables whose term is being copied
    cyclic::Dict{UInt64, T}             # a bound variable met again in progress → its placeholder
end

# PORT: pl-copyterm.c copy_term
# DIVERGES: see the file header — one bottom-up walk over values; the cyclic copy is a fresh
# variable bound to the copy; a compound met both directly and through its variable is copied
# twice (the header's CELL IDENTITY: no answer differs, `same_term/2` would — step L1).
# TRANSITIONAL (f3b-3, class (c)): the term copy (`_cp_visit!`, `_cp_finish!`): callers
# copy_term_refs' and copy_exception!'s CP_BOUNDARY and the records' boundary
# (`_compileTermToHeap_terms`); deleted in f3
"""
    copy_term(ld, from, options) -> T

A copy of `from` under the bindings in `ld`: variables renamed consistently, ground subterms
shared where `options.share`, a cyclic term copied as a cyclic term (pl-copyterm.c `copy_term`).
"""
function copy_term(ld::PL_local_data{T}, from::T, options::cp_options)::T where {T}
    return copy_term(ld, from, options, Dict{UInt64, T}())
end

# ORIGINAL: the walk with the caller's map of fresh variables — an unbound variable already in
# `vars` is copied to its entry, a new one is added to it — so that several copies share their
# variables, as the arguments of one record do (`putSlotValue!`'s until f3b-1, which lays a
# caller's value on the cells now: no src caller passes a map since; the term walk goes in f3).
"`copy_term` with the fresh variables of `vars` (an unbound variable's key → its copy), extended in place."
function copy_term(
    ld::PL_local_data{T}, from::T, options::cp_options, vars::Dict{UInt64, T}
)::T where {T}
    st = _cp_state{T}(
        options.share, vars, Dict{UInt64, T}(), Set{UInt64}(), Dict{UInt64, T}()
    )
    stack = _cp_frame{T}[]
    result = _cp_visit!(ld, st, stack, from)
    while !isempty(stack)
        f = stack[end]
        if f.next <= length(f.kids)
            i = f.next
            f.next += 1
            c = child(f.orig, i)
            r = _cp_visit!(ld, st, stack, c)
            if r !== nothing                            # a finished child: no frame was pushed
                f.kids[i] = r
                r === c || (f.same = false)
            end
        else
            pop!(stack)
            r = _cp_finish!(ld, st, f)
            if isempty(stack)
                result = r
            else
                p = stack[end]
                i = p.next - 1                          # the parent's child being completed
                p.kids[i] = r
                r === child(p.orig, i) || (p.same = false)
            end
        end
    end
    return result::T
end

# Visit term `t`: follow its bound variables (noting them), then an unbound variable and an atomic
# are finished at once (the copy is returned) and a compound gets a frame (`nothing` is returned).
function _cp_visit!(
    ld::PL_local_data{T}, st::_cp_state{T}, stack::Vector{_cp_frame{T}}, t::T
)::Union{Nothing, T} where {T}
    chain = UInt64[]
    while kind(t) === VAR
        k = var_key(t)
        # TRANSITIONAL (f3b-3, class (c)): a bound variable followed by key, reached only through
        # CP_BOUNDARY / the records' boundary (census evidence/f3b-3); deleted in f3
        b = _binding(ld, k)
        b === nothing && break
        if haskey(st.done, k)                           # copied already
            return _cp_chain_done!(st, chain, st.done[k])
        end
        if k in st.inprogress                           # a cycle: its copy is a variable, bound later
            # a KEYED variable, not a cell (L1a): `copy_exception!` drops its binding's trail entry
            # to freeze a cyclic ball, which a cell's binding would not survive (`Undo!` frees the
            # cell); bound at once, it is never compared unbound, so its key's order is not seen
            w = get!(() -> mk_var(T, fresh_var_keys!(1)), st.cyclic, k)
            return _cp_chain_done!(st, chain, w)
        end
        push!(chain, k)
        t = b
    end
    kt = kind(t)
    if kt === VAR                                       # unbound: one fresh variable per variable
        # TRANSITIONAL (f3b-3, class (c)): the copy's fresh variable as a cell term; deleted in f3
        w = get!(() -> _cell_var(ld, allocGlobalCells!(ld, 1)), st.vars, var_key(t))
        return _cp_chain_done!(st, chain, w)
    elseif kt !== EXPR
        return _cp_chain_done!(st, chain, t)
    end
    union!(st.inprogress, chain)
    push!(stack, _cp_frame{T}(t, Vector{T}(undef, nchildren(t)), 1, true, chain))
    return nothing
end

# The copy `r` is the copy of every variable of `chain`.
function _cp_chain_done!(st::_cp_state{T}, chain::Vector{UInt64}, r::T)::T where {T}
    for k in chain
        st.done[k] = r
    end
    return r
end

# A compound's children are all copied: share it or build the copy; and bind the placeholders of
# the bound variables it was reached through, which a cycle met.
function _cp_finish!(ld::PL_local_data{T}, st::_cp_state{T}, f::_cp_frame{T})::T where {T}
    r = (st.share && f.same) ? f.orig : mk_expr(T, f.kids)
    for k in f.chain
        delete!(st.inprogress, k)
    end
    out = r
    for k in f.chain
        w = get(st.cyclic, k, nothing)
        if w !== nothing
            Trail!(ld, var_key(w), r)                   # the cyclic copy: w = r, and r holds w
            out = w
        end
        st.done[k] = out
    end
    return out
end

# ── copying on the CELLS (L1d step 6; the workspace's L1_plan/stageL1d_design.md §3f) ───────────
# Upstream's three passes on locations: mark (`mark_for_copy`, `mark_for_duplicate`), copy
# (`copy_term`, its originals forwarded and trailed on `ld.cp_lstack`), restore (`exitCyclicCopy`),
# unmark (`cp_unmark`). A FUNCTOR cell carries its marks in place (MARK|FIRST, as upstream); a
# VARIABLE cell's marks, and VAR_MARK on a copy's cell, live in the side vector `ld.cp_vmarks` by
# position — upstream writes them into the variable cell, which ours cannot (a marked variable cell
# is no `isVar`, and `_deref_loc` would read it as a value-table word): a representation-only
# DIVERGES, behaviour identical. The term walk above (`copy_term`) stays for the callers holding a
# TERM (the records' and the exception's ball's boundary; `putSlotValue!` until f3b-1) and for the BOUNDARY: a keyed variable's
# binding or a slot's side value met while marking — the whole copy is then redone on terms,
# counted in `cold_pairs`. TRANSITIONAL until L1f.

# PORT: pl-copyterm.c BOTH_MASK
"The two copy marks (pl-copyterm.c `BOTH_MASK`): MARK (visited) and FIRST."
const BOTH_MASK = MARK_MASK | FIRST_MASK
# The side vector's bits: MARK and FIRST of a variable cell, and VAR_MARK on a copy's cell.
const _CPV_MARK = 0x01
const _CPV_FIRST = 0x02
const _CPV_BOTH = 0x03
const _CPV_VARMARK = 0x04
"`mark_for_copy_cells`: the walk met the boundary (a keyed variable, a slot's side value)."
const CP_BOUNDARY = -1

# ORIGINAL: the side vector's entry of global position `p` (0 beyond its end).
@inline _cp_vm(ld::PL_local_data, p::Int)::UInt8 =
    p <= length(ld.cp_vmarks) ? ld.cp_vmarks[p] : 0x00

# ORIGINAL: set the side vector's entry of global position `p`, growing it (new entries 0).
function _cp_vm!(ld::PL_local_data, p::Int, v::UInt8)::Nothing
    s = ld.cp_vmarks
    n = length(s)
    if p > n
        resize!(s, max(p, 2 * n, 64))
        fill!(view(s, (n + 1):length(s)), 0x00)
    end
    s[p] = v
    return nothing
end

# ORIGINAL: the word at location `l` (a global position, or `-i` for slot `i`), not dereferenced.
@inline _cp_word(ld::PL_local_data, l::Int)::word = l > 0 ? ld.gstack[l] : ld.slots[-l]

# ORIGINAL: whether the word `c` at location `l` is the boundary (a slot's side value, or a
# value-table word holding a keyed variable).
@inline function _cp_boundary(ld::PL_local_data{T}, l::Int, c::word)::Bool where {T}
    l < 0 && c == SLOT_VALUE && return true                  # (a slot's value-table word: below, L1e e1)
    (isVar(c) || isRef(c) || isAtomW(c) || _is_gcompound(c) || isTaggedIntW(c)) &&
        return false
    return kind(ld.vtable[valPtr(c)]) === VAR
end

# PORT: pl-copyterm.c can_share as can_share_cells
"Whether the argument cell at global position `p` can be shared by a copy (pl-copyterm.c)."
function can_share_cells(ld::PL_local_data, p::Int)::Bool
    c = ld.gstack[p]
    while isRef(c)                                          # TAG_REFERENCE
        p = unRef(c)
        c = ld.gstack[p]
    end
    isVar(c) && return false                                # TAG_VAR: no COPY_MARKED
    _is_gcompound(c) && return (ld.gstack[valPtr(c)] & BOTH_MASK) == FIRST_MASK   # is_ground
    return true
end

# PORT: pl-copyterm.c update_ground as update_ground_cells
"Mark the compound whose word is at location `l` ground when every argument can be shared (pl-copyterm.c)."
function update_ground_cells(ld::PL_local_data, l::Int)::Nothing
    q = valPtr(_cp_word(ld, l))
    f = ld.gstack[q]
    for a in (q + arityFunctor(ld.functors, f)):-1:(q + 1)
        can_share_cells(ld, a) || return nothing
    end
    ld.gstack[q] = (f & ~MARK_MASK) | FIRST_MASK            # set_ground
    return nothing
end

# PORT: pl-copyterm.c mark_for_copy as mark_for_copy_cells
# DIVERGES: on locations, the stack `ld.cp_stack` of `(loc << 1) | walk_ref`; no attributed variable
# (MC_WALK_COPY, `must_copy_attvar`, `unshare_attvar`), no COPY_MARKED. As upstream, a compound is
# dispatched again after `update_ground` (its functor visited once → shared). Returns 1, or
# `CP_BOUNDARY`.
"Mark the term at location `start` for `copy_term` (pl-copyterm.c `mark_for_copy`): 1, or `CP_BOUNDARY`."
function mark_for_copy_cells(ld::PL_local_data{T}, start::Int)::Int where {T}
    stack = ld.cp_stack
    base = length(stack)
    p = start
    wr = false                                              # mode & MC_WALK_REF
    while true
        c = _cp_word(ld, p)                                 # switch(tag(*p))
        if _cp_boundary(ld, p, c)
            resize!(stack, base)
            return CP_BOUNDARY
        elseif isRef(c)                                     # TAG_REFERENCE
            push!(stack, (p << 1) | Int(wr))
            wr = true
            p = unRef(c)                                    # deRef(p)
            while isRef(ld.gstack[p])
                p = unRef(ld.gstack[p])
            end
            continue
        elseif isVar(c)                                     # TAG_VAR
            m = _cp_vm(ld, p)
            if (m & _CPV_BOTH) == 0                         # virgin && COPY_ALWAYS
                _cp_vm!(ld, p, m | _CPV_MARK)
            elseif (m & _CPV_BOTH) == _CPV_MARK             # visited_once
                _cp_vm!(ld, p, m | _CPV_BOTH)
            elseif (m & _CPV_BOTH) == _CPV_FIRST            # must_copy
                _cp_vm!(ld, p, (m & ~_CPV_BOTH) | _CPV_MARK)
            end
        elseif _is_gcompound(c)                             # TAG_COMPOUND
            q = valPtr(c)
            f = ld.gstack[q]
            arity = arityFunctor(ld.functors, f)
            if (f & BOTH_MASK) == 0                         # virgin(t->definition)
                ld.gstack[q] = f | MARK_MASK
                if arity >= 1
                    push!(stack, (p << 1) | Int(wr))
                    wr = false
                    p = q + arity                           # last argument
                    continue
                end
            elseif (f & BOTH_MASK) == MARK_MASK             # visited_once
                ld.gstack[q] = f | BOTH_MASK                # set_shared
            end
        end
        if p == start                                       # after a leaf
            resize!(stack, base)
            return 1
        end
        while wr
            e = pop!(stack)
            p, wr = e >> 1, (e & 1) != 0
            if p == start
                resize!(stack, base)
                return 1
            end
        end
        p -= 1
        if isFunctor(ld.gstack[p])                          # functor (compound)
            e = pop!(stack)
            p, wr = e >> 1, (e & 1) != 0
            update_ground_cells(ld, p)
        end
    end
end

# PORT: pl-copyterm.c mark_for_duplicate as mark_for_duplicate_cells
# DIVERGES: on locations, the one-sided cell agenda; no `nshare` (duplicate_term/2 shares nothing).
"Mark the term at location `l` for `duplicate_term` (pl-copyterm.c `mark_for_duplicate`): 1, or `CP_BOUNDARY`."
function mark_for_duplicate_cells(ld::PL_local_data{T}, l::Int)::Int where {T}
    a = ld.walk_agenda
    initCellAgenda!(a, 1, l)
    while true
        q = nextCellAgendaNoDeRef!(a)
        q == 0 && break
        k, w, p = _deref_loc(ld, q)                         # nextTermAgenda: deRef(p)
        if k == DU_TERM
            clearCellAgenda!(a)
            return CP_BOUNDARY
        elseif k == DU_CELL                                 # TAG_VAR
            m = _cp_vm(ld, p)
            if (m & _CPV_BOTH) == 0
                _cp_vm!(ld, p, m | _CPV_MARK)
            elseif (m & _CPV_BOTH) == _CPV_MARK
                _cp_vm!(ld, p, m | _CPV_BOTH)
            end
        elseif k == DU_WORD && _is_gcompound(w)             # TAG_COMPOUND
            c = valPtr(w)
            f = ld.gstack[c]
            if (f & BOTH_MASK) == 0
                ld.gstack[c] = f | MARK_MASK
                pushWorkCellAgenda!(a, arityFunctor(ld.functors, f), c + 1)
            elseif (f & BOTH_MASK) == MARK_MASK
                ld.gstack[c] = f | BOTH_MASK
            end
        end
    end
    return 1
end

# PORT: pl-copyterm.c cp_unmark as cp_unmark_cells
# DIVERGES: a variable cell's marks are its side-vector bits (see the section header); the boundary
# (`DU_TERM`) holds no mark.
"Clear the copy marks of the term at location `l` (pl-copyterm.c `cp_unmark`)."
function cp_unmark_cells(ld::PL_local_data{T}, l::Int)::Nothing where {T}
    a = ld.walk_agenda
    initCellAgenda!(a, 1, l)
    while true
        q = nextCellAgendaNoDeRef!(a)
        q == 0 && break
        k, w, p = _deref_loc(ld, q)
        if k == DU_CELL                                     # TAG_VAR: *p &= ~BOTH_MASK
            m = _cp_vm(ld, p)
            m & _CPV_BOTH != 0 && _cp_vm!(ld, p, m & ~_CPV_BOTH)
        elseif k == DU_WORD && _is_gcompound(w)             # TAG_COMPOUND
            c = valPtr(w)
            f = ld.gstack[c]
            if (f & BOTH_MASK) != 0                         # visited(f->definition)
                ld.gstack[c] = f & ~BOTH_MASK
                pushWorkCellAgenda!(a, arityFunctor(ld.functors, f), c + 1)
            end
        end
    end
    return nothing
end

# PORT: pl-copyterm.c exitCyclicCopy as exitCyclicCopy_cells
# DIVERGES: VAR_MARK is the side vector's bit on the copy's cell (the cell itself stays 0); the
# forwarded cells are on `ld.cp_lstack` (upstream: `LD->cycle.lstack`); no attributed variable.
"Restore every original cell the copy forwarded (pl-copyterm.c `exitCyclicCopy`)."
function exitCyclicCopy_cells(ld::PL_local_data)::Nothing
    s = ld.cp_lstack
    while !isempty(s)
        p = pop!(s)
        p2 = unRef(ld.gstack[p])
        m = _cp_vm(ld, p2)
        if isVar(ld.gstack[p2]) && (m & _CPV_VARMARK) != 0  # sharing variables
            _cp_vm!(ld, p2, m & ~_CPV_VARMARK)              # setVar(*p2)
            ld.gstack[p] = word(0)                          # setVar(*p)
        else
            ld.gstack[p] = ld.gstack[p2] | MARK_MASK        # cyclic terms
        end
    end
    return nothing
end

# PORT: pl-copyterm.c copy_term as copy_term_cells
# DIVERGES: on locations, the two-sided cell agenda (upstream's term_agendaLRD; no COPY_ABSTRACT, so
# no depth); `to` is always a global position; a copy's cell holding VAR_MARK is an unbound cell
# with the side-vector bit. No attributed variable, no COPY_MARKED. A compound's cells are
# `allocGlobalNoShift`'s: `GLOBAL_OVERFLOW` when they pass the limit (L1f f1b), as upstream's.
"Copy the marked term at location `from` into the unbound global cell `to` (pl-copyterm.c `copy_term`): `BOOLEX_TRUE` or `GLOBAL_OVERFLOW`."
function copy_term_cells(ld::PL_local_data{T}, from::Int, to::Int)::boolex_t where {T}
    a = ld.cp_agenda
    initCellAgendaLR!(a, 1, from, to, 0)
    while true
        found, f, t = nextCellAgendaLR!(a)
        found || break
        while true                                          # again:
            c = _cp_word(ld, f)
            if isRef(c)                                     # TAG_REFERENCE
                p2 = unRef(c)
                if isVar(ld.gstack[p2]) && (_cp_vm(ld, p2) & _CPV_VARMARK) != 0
                    ld.gstack[t] = makeRefG(p2)             # a reference to a copied variable
                    break
                end
                f = p2                                      # a normal reference
                continue
            elseif isVar(c)                                 # TAG_VAR
                ld.gstack[t] = word(0)
                if (_cp_vm(ld, f) & _CPV_BOTH) == _CPV_BOTH # shared(*from)
                    _cp_vm!(ld, t, _cp_vm(ld, t) | _CPV_VARMARK)   # *to = VAR_MARK
                    ld.gstack[f] = makeRefG(t)              # *from = makeRefG(to)
                    push!(ld.cp_lstack, f)                  # TrailCyclic(from)
                end
            elseif _is_gcompound(c)                         # TAG_COMPOUND
                ff = valPtr(c)
                fd = ld.gstack[ff]
                if isRef(fd)                                # copied already (forwarded)
                    ld.gstack[t] = consPtr(unRef(fd), TAG_COMPOUND | STG_GLOBAL)
                elseif (fd & BOTH_MASK) == FIRST_MASK       # is_ground: shared
                    ld.gstack[t] = c
                else
                    arity = arityFunctor(ld.functors, fd)
                    ft = allocGlobalNoShift(ld, arity + 1)
                    if ft == 0                              # rc = GLOBAL_OVERFLOW; goto out
                        clearCellAgendaLR!(a)
                        return GLOBAL_OVERFLOW
                    end
                    ld.gstack[ft] = fd & ~BOTH_MASK
                    if (fd & BOTH_MASK) == BOTH_MASK        # shared: forward the original
                        ld.gstack[ff] = makeRefG(ft)
                        push!(ld.cp_lstack, ff)             # TrailCyclic(&ff->definition)
                    end
                    ld.gstack[t] = consPtr(ft, TAG_COMPOUND | STG_GLOBAL)
                    pushWorkCellAgendaLR!(a, arity, ff, ft, 1)
                end
            else                                            # an atomic word (an indirect shared)
                ld.gstack[t] = c
            end
            break
        end
    end
    clearCellAgendaLR!(a)
    return BOOLEX_TRUE
end

# PORT: pl-copyterm.c do_copy_term as do_copy_term_cells
# DIVERGES: `from` a location (dereferenced here), `to` an unbound global cell; returns 1 (true),
# `Int(GLOBAL_OVERFLOW)` (L1f f1b), or `CP_BOUNDARY`, after unmarking — the caller redoes the copy on
# terms.
"Copy the term at location `from` into the unbound global cell `to` (pl-copyterm.c `do_copy_term`): 1, `Int(GLOBAL_OVERFLOW)` or `CP_BOUNDARY`."
function do_copy_term_cells(
    ld::PL_local_data{T}, from::Int, to::Int, options::cp_options
)::Int where {T}
    k, w, p = _deref_loc(ld, from)
    k == DU_CELL && return 1                                # TAG_VAR: `to` stays a fresh variable
    k == DU_TERM && return CP_BOUNDARY
    if !(k == DU_WORD && _is_gcompound(w))                  # an atomic: *to = *from
        nw = _value_word!(ld, w)                            # (an indirect's word: shared; a slot's
        ld.gstack[to] = nw                                  #  side value its own word, f3-1)
        return 1
    end
    src = p > 0 ? p : from                                  # the location holding the compound's word
    rc = options.share ? mark_for_copy_cells(ld, src) : mark_for_duplicate_cells(ld, src)
    if rc != 1
        cp_unmark_cells(ld, src)
        return rc
    end
    rc2 = copy_term_cells(ld, src, to)                      # initCyclicCopy: nothing to do
    exitCyclicCopy_cells(ld)
    cp_unmark_cells(ld, src)
    return Int(rc2)
end

# ── the built-ins ───────────────────────────────────────────────────────────────────────────────
# PORT: pl-copyterm.c copy_term_refs
# DIVERGES: on the CELLS (L1d step 6): a fresh global cell, `to` its `makeRefG`, as upstream; no `vars`
# (copy_term/4). The loop is upstream's (L1f f1b): a copy that does not fit is discarded with its
# foreign frame and `makeMoreStackSpace` asked — which here raises the overflow (see there). The
# boundary (see the section above) copies on terms, counted in `cold_pairs`.
"Make term reference `to` hold a copy of the term `from` references; false, the overflow raised, when it does not fit (pl-copyterm.c)."
function copy_term_refs(
    ld::PL_local_data{T}, from::term_t, to::term_t, options::cp_options
)::Bool where {T}
    while true
        fid = PL_open_foreign_frame(ld)
        ensureGlobalSpace(ld, 1) || (PL_close_foreign_frame(ld, fid); return false)
        dest = allocGlobalCells!(ld, 1)                     # dest = allocGlobal(1); setVar(*dest)
        ld.slots[to + 1] = makeRefG(dest)                   # *valTermRef(to) = makeRefG(dest)
        rc = do_copy_term_cells(ld, -(from + 1), dest, options)
        # TRANSITIONAL (f3b-3, class (c)): the boundary's term copy; deleted in f3
        if rc == CP_BOUNDARY
            ld.cold_pairs += 1
            setSlotValue!(ld, to + 1, copy_term(ld, slotValue(ld, from + 1), options))
            rc = 1
        end
        if rc < 0                                           # no space for copy
            PL_discard_foreign_frame(ld, fid)
            _slot_new_var!(ld, to + 1)                      # PL_put_variable(to): gc consistency
            makeMoreStackSpace(ld, GLOBAL_OVERFLOW, ALLOW_SHIFT) || return false
        else
            PL_close_foreign_frame(ld, fid)
            return true
        end
    end
end

# PORT: pl-copyterm.c copy_term as pl_copy_term2_va
# (PRED_IMPL("copy_term", 2, copy_term, 0)); the table's flag is `PL_FA_ISO`.
"`copy_term(+In, -Out)`: `Out` is `In` with its variables renamed, ground subterms shared."
function pl_copy_term2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    if PL_is_atomic(ld, A1)                                 # if ( PL_is_atomic(A1) )
        return PL_unify(ld, A1, A2) ? FTRUE : FFALSE
    end
    copy = PL_new_term_ref(ld)
    copy_term_refs(ld, A1, copy, cp_options(true)) || return FFALSE
    return PL_unify(ld, copy, A2) ? FTRUE : FFALSE
end

# PORT: pl-copyterm.c copy_term_nat as pl_copy_term_nat2_va
# (PRED_IMPL("copy_term_nat", 2, copy_term_nat, 0)) — no attributes either way, so as copy_term/2.
"`copy_term_nat(+In, -Out)`: `copy_term/2` without attributes."
function pl_copy_term_nat2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    copy = PL_new_term_ref(ld)                              # (upstream has no atomic shortcut here)
    copy_term_refs(ld, A1, copy, cp_options(true)) || return FFALSE
    return PL_unify(ld, copy, A2) ? FTRUE : FFALSE
end

# PORT: pl-copyterm.c duplicate_term as pl_duplicate_term2_va
# (PRED_IMPL("duplicate_term", 2, duplicate_term, 0))
"`duplicate_term(+In, -Out)`: `Out` is a copy of `In` that shares no compound with it."
function pl_duplicate_term2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    if PL_is_atomic(ld, A1)                                 # if ( PL_is_atomic(A1) )
        return PL_unify(ld, A1, A2) ? FTRUE : FFALSE
    end
    copy = PL_new_term_ref(ld)
    copy_term_refs(ld, A1, copy, cp_options(false)) || return FFALSE
    return PL_unify(ld, copy, A2) ? FTRUE : FFALSE
end

# PORT: pl-copyterm.c BeginPredDefs as PL_predicates_from_copyterm
# DIVERGES: the ported entries only (upstream's table also has `copy_term/4`, `copy_term_nat/4`,
# `size_abstract_term/3`, `$fast_record/2`, `$fast_recorded/2`).
"pl-copyterm.c's registration table (`BeginPredDefs(copyterm)`): the ported entries."
const PL_predicates_from_copyterm = (
    PL_extension("copy_term", 2, pl_copy_term2_va, PL_FA_VARARGS | PL_FA_ISO),
    PL_extension("duplicate_term", 2, pl_duplicate_term2_va, PL_FA_VARARGS),
    PL_extension("copy_term_nat", 2, pl_copy_term_nat2_va, PL_FA_VARARGS)
)
