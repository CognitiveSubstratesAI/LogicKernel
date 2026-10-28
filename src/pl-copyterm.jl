# UPSTREAM: swipl-devel src/pl-copyterm.c @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2026, University of Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# COPYING TERMS — SWI-Prolog's `copy_term/2`, `copy_term_nat/2` and `duplicate_term/2`, with attributed
# variables (AV6; `copy_term/3` is R2's).
#
# WHAT UPSTREAM DOES. A term is copied with its variables renamed consistently — a variable met twice
# becomes one fresh variable met twice — and, under `COPY_SHARE` (`copy_term/2`), a GROUND subterm is
# not copied but shared with the original; `duplicate_term/2` copies every compound. Upstream uses the
# GC mark bits of the global stack to classify each cell (virgin, visited, shared, ground) in a
# marking pass (`mark_for_copy`, `mark_for_duplicate`), then copies (`copy_term`), then clears the
# marks (`cp_unmark`); cyclic terms are copied by `initCyclicCopy`'s link table.
#
# WHAT THE KERNEL DOES. Upstream's passes on the cells (since L1d step 6; the term-level walk over
# keyed bindings went in L1f f3): see the section below for the marks a variable cell keeps beside
# the stack.
#
# Attributed variables (AV6): `COPY_ATTRS` copies an attvar's attribute list into a new attvar
# (`alloc_attvar`), without it (`copy_term_nat/2`) an attvar is copied as a plain variable.
# NOT PORTED: `copy_term/4`, `copy_term_nat/4` (`COPY_MARKED`, `mark_vars`, so `COPYING_ATTVAR` and
# `MC_WALK_COPY`: their only readers are `COPY_MARKED` tests), `size_abstract_term/3`
# (`COPY_ABSTRACT`), `duplicate_term`'s `nshare`/`share` (the shared subterms of `duplicate_term/2`
# are none: `nshare` is 0) and the fast heap terms (`$fast_record`, `term_to_fastheap`).

# PORT: pl-copyterm.c COPY_SHARE
"Share ground terms (pl-copyterm.c `COPY_SHARE`)."
const COPY_SHARE = 0x01
# PORT: pl-copyterm.c COPY_ATTRS
"Copy attributes (pl-copyterm.c `COPY_ATTRS`)."
const COPY_ATTRS = 0x02

# PORT: pl-copyterm.c cp_options
# DIVERGES: `flags` only (no `abstract`, `nshare`, `share`: `size_abstract_term/3` and duplicate_term's
# shared subterms are not ported).
"The options of a copy (pl-copyterm.c `cp_options`): its `flags`, `COPY_SHARE` and `COPY_ATTRS`."
struct cp_options
    flags::Int
end

# ── copying on the CELLS (L1d step 6; the workspace's L1_plan/stageL1d_design.md §3f) ───────────
# Upstream's three passes on locations: mark (`mark_for_copy`, `mark_for_duplicate`), copy
# (`copy_term`, its originals forwarded and trailed on `ld.cp_lstack`), restore (`exitCyclicCopy`),
# unmark (`cp_unmark`). A FUNCTOR cell carries its marks in place (MARK|FIRST, as upstream); a
# VARIABLE cell's marks, and VAR_MARK on a copy's cell, live in the side vector `ld.cp_vmarks` by
# position — upstream writes them into the variable cell, which ours cannot (a marked variable cell
# is no `isVar`, and `_deref_loc` would read it as a value-table word): a representation-only
# DIVERGES, behaviour identical. A slot's side value (D-0024's indirect, f3-1) is copied as the
# value it holds (`do_copy_term_cells`: its value's word).

# PORT: pl-copyterm.c BOTH_MASK
"The two copy marks (pl-copyterm.c `BOTH_MASK`): MARK (visited) and FIRST."
const BOTH_MASK = MARK_MASK | FIRST_MASK
# The side vector's bits: MARK and FIRST of a variable cell, and VAR_MARK on a copy's cell.
const _CPV_MARK = 0x01
const _CPV_FIRST = 0x02
const _CPV_BOTH = 0x03
const _CPV_VARMARK = 0x04

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

# PORT: pl-copyterm.c can_share as can_share_cells
"Whether the argument cell at global position `p` can be shared by a copy (pl-copyterm.c)."
function can_share_cells(ld::PL_local_data, p::Int)::Bool
    c = ld.gstack[p]
    while isRef(c)                                          # TAG_REFERENCE
        p = unRef(c)
        c = ld.gstack[p]
    end
    (isVar(c) || isAttVar(c)) && return false               # TAG_VAR, TAG_ATTVAR: no COPY_MARKED
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

# PORT: pl-copyterm.c unshare_attvar as unshare_attvar_cells
# DIVERGES: positions. As upstream, a compound that is not `att/3` leaves `p` where it is (the loop
# does not end: an attribute list is `att/3` cells by put_attr/3; put_attrs/2's is the caller's).
"Mark the `att/3` cells of the attribute list at global position `p` visited once, so none is shared as ground (pl-copyterm.c)."
function unshare_attvar_cells(ld::PL_local_data{T}, p::Int)::Nothing where {T}
    fatt3 = _functor_att3(ld)
    while true
        while isRef(ld.gstack[p])                           # deRef(p)
            p = unRef(ld.gstack[p])
        end
        c = ld.gstack[p]
        _is_gcompound(c) || return nothing                  # if ( isTerm(*p) ) … else break
        q = valPtr(c)
        fd = ld.gstack[q] & ~BOTH_MASK
        if fd == fatt3
            ld.gstack[q] = fd | MARK_MASK                   # t->definition = fd | MARK_MASK
            p = q + 3                                       # p = &t->arguments[2]
        end
    end
end

# PORT: pl-copyterm.c must_copy_attvar
# DIVERGES: no `COPY_MARKED` (copy_term/4 is not ported), so no `w` and no `mode`.
"Whether the marking walks into an attributed variable's attributes (pl-copyterm.c `must_copy_attvar`)."
@inline must_copy_attvar(flags::Int)::Bool = (flags & COPY_ATTRS) != 0

# PORT: pl-copyterm.c mark_for_copy as mark_for_copy_cells
# DIVERGES: on locations, the stack `ld.cp_stack` of `(loc << 1) | walk_ref`; no COPY_MARKED, so of the
# mode only MC_WALK_REF (MC_WALK_COPY's readers are COPY_MARKED tests). An attributed variable's marks
# are in its word, as upstream (its tag survives them). As upstream, a compound is dispatched again
# after `update_ground` (its functor visited once → shared). Returns 1.
"Mark the term at location `start` for `copy_term` (pl-copyterm.c `mark_for_copy`): 1."
function mark_for_copy_cells(ld::PL_local_data{T}, start::Int, flags::Int)::Int where {T}
    stack = ld.cp_stack
    base = length(stack)
    p = start
    wr = false                                              # mode & MC_WALK_REF
    while true
        c = _cp_word(ld, p)                                 # switch(tag(*p))
        if isRef(c)                                         # TAG_REFERENCE
            push!(stack, (p << 1) | Int(wr))
            wr = true
            p = unRef(c)                                    # deRef(p)
            while isRef(ld.gstack[p])
                p = unRef(ld.gstack[p])
            end
            continue
        elseif isAttVar(c) && must_copy_attvar(flags)       # TAG_ATTVAR
            push!(stack, (p << 1) | Int(wr))
            wr = true                                       # mode |= MC_WALK_REF|MC_WALK_COPY
            p = valPtr(c & ~BOTH_MASK)                      # p = valPAttVar(*p & ~BOTH_MASK)
            continue
        elseif isAttVar(c)                                  # TAG_ATTVAR → TAG_VAR: marks in the word
            if (c & BOTH_MASK) == 0                         # virgin && COPY_ALWAYS
                ld.gstack[p] = c | MARK_MASK
            elseif (c & BOTH_MASK) == MARK_MASK             # visited_once
                ld.gstack[p] = c | BOTH_MASK
            elseif (c & BOTH_MASK) == FIRST_MASK            # must_copy
                ld.gstack[p] = (c & ~BOTH_MASK) | MARK_MASK
            end
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
            pw = _cp_word(ld, p)
            if isAttVar(pw)                                 # if ( isAttVar(*p) )
                unshare_attvar_cells(ld, valPtr(pw & ~BOTH_MASK))
            end
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
# An attributed variable's marks are in its word, as upstream.
"Mark the term at location `l` for `duplicate_term` (pl-copyterm.c `mark_for_duplicate`): 1."
function mark_for_duplicate_cells(ld::PL_local_data{T}, l::Int, flags::Int)::Int where {T}
    a = ld.walk_agenda
    initCellAgenda!(a, 1, l)
    while true
        q = nextCellAgendaNoDeRef!(a)
        q == 0 && break
        k, w, p = _deref_loc(ld, q)                         # nextTermAgenda: deRef(p)
        while k == DU_ATTVAR && (flags & COPY_ATTRS) != 0   # TAG_ATTVAR, COPY_ATTRS:
            p = valPtr(w)                                   #   p = valPAttVar(*p); goto again
            w = ld.gstack[p]                                #   (no deRef: a reference has no case)
            k = if isVar(w)
                DU_CELL
            elseif isAttVar(w)
                DU_ATTVAR
            else
                DU_WORD
            end
        end
        if k == DU_ATTVAR                                   # TAG_ATTVAR → TAG_VAR (no COPY_ATTRS)
            if (w & BOTH_MASK) == 0                         # virgin: set_visited
                ld.gstack[p] = w | MARK_MASK
            elseif (w & BOTH_MASK) == MARK_MASK             # visited_once: set_shared
                ld.gstack[p] = w | BOTH_MASK
            end
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
# DIVERGES: a variable cell's marks are its side-vector bits (see the section header); an attributed
# variable's are in its word, as upstream. No COPY_MARKED.
"Clear the copy marks of the term at location `l` (pl-copyterm.c `cp_unmark`)."
function cp_unmark_cells(ld::PL_local_data{T}, l::Int, flags::Int)::Nothing where {T}
    a = ld.walk_agenda
    initCellAgenda!(a, 1, l)
    while true
        q = nextCellAgendaNoDeRef!(a)
        q == 0 && break
        k, w, p = _deref_loc(ld, q)
        while k == DU_ATTVAR && (flags & COPY_ATTRS) != 0   # TAG_ATTVAR, COPY_ATTRS:
            p = valPtr(w)                                   #   p = valPAttVar(*p); goto again
            w = ld.gstack[p]                                #   (no deRef: a reference has no case)
            k = if isVar(w)
                DU_CELL
            elseif isAttVar(w)
                DU_ATTVAR
            else
                DU_WORD
            end
        end
        if k == DU_ATTVAR                                   # TAG_ATTVAR → TAG_VAR: *p &= ~BOTH_MASK
            ld.gstack[p] = w & ~BOTH_MASK
        elseif k == DU_CELL                                 # TAG_VAR: *p &= ~BOTH_MASK
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
# forwarded cells are on `ld.cp_lstack` (upstream: `LD->cycle.lstack`); an attributed variable's entry is
# two, `old` (its attribute-list cell) under the attvar cell, told apart by `isRef` as upstream.
"Restore every original cell the copy forwarded (pl-copyterm.c `exitCyclicCopy`)."
function exitCyclicCopy_cells(ld::PL_local_data, flags::Int)::Nothing
    s = ld.cp_lstack
    while !isempty(s)
        p = pop!(s)
        c = ld.gstack[p]
        if !isRef(c)                                        # an attributed variable
            old = pop!(s)                                   # popSegStack(&LD->cycle.lstack, &old, Word)
            if (flags & COPY_ATTRS) == 0
                p2 = valPtr(c & ~BOTH_MASK)
                @assert isVar(ld.gstack[p2]) && (_cp_vm(ld, p2) & _CPV_VARMARK) != 0   # *p2 == VAR_MARK
                _cp_vm!(ld, p2, _cp_vm(ld, p2) & ~_CPV_VARMARK)                       # setVar(*p2)
            end
            ld.gstack[p] = consPtr(old, STG_GLOBAL | TAG_ATTVAR)
            continue
        end
        p2 = unRef(c)
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
# with the side-vector bit (also under an attributed variable's forwarded word, without COPY_ATTRS).
# No COPY_MARKED. A compound's cells, and a copied attvar's (`alloc_attvar`), are `allocGlobalNoShift`'s:
# `GLOBAL_OVERFLOW` when they pass the limit (since L1f f1b), as upstream's.
"Copy the marked term at location `from` into the unbound global cell `to` (pl-copyterm.c `copy_term`): `BOOLEX_TRUE` or `GLOBAL_OVERFLOW`."
function copy_term_cells(
    ld::PL_local_data{T}, from::Int, to::Int, flags::Int
)::boolex_t where {T}
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
            elseif isAttVar(c)                              # TAG_ATTVAR
                p = valPtr(c & ~BOTH_MASK)                  # p = valPAttVar(*from & ~BOTH_MASK)
                if (flags & COPY_ATTRS) != 0
                    if isAttVar(ld.gstack[p])               # already copied
                        ld.gstack[t] = makeRefG(p)
                        break
                    end
                    attr = alloc_attvar(ld)                 # (no COPY_MARKED: always copied)
                    if attr == 0                            # rc = GLOBAL_OVERFLOW; goto out
                        clearCellAgendaLR!(a)
                        return GLOBAL_OVERFLOW
                    end
                    push!(ld.cp_lstack, p)                  # TrailCyclic(p)
                    push!(ld.cp_lstack, f)                  # TrailCyclic(from)
                    ld.gstack[f] = consPtr(attr, STG_GLOBAL | TAG_ATTVAR)
                    ld.gstack[t] = makeRefG(attr)
                    f = p                                   # from = p; to = &attr[1]; goto again
                    t = attr + 1
                    continue
                elseif (c & BOTH_MASK) == BOTH_MASK         # shared(*from)
                    if isVar(ld.gstack[p]) && (_cp_vm(ld, p) & _CPV_VARMARK) != 0   # *p == VAR_MARK
                        ld.gstack[t] = makeRefG(p)
                    else
                        ld.gstack[t] = word(0)              # *to = VAR_MARK
                        _cp_vm!(ld, t, _cp_vm(ld, t) | _CPV_VARMARK)
                        ld.gstack[f] = consPtr(t, STG_GLOBAL | TAG_ATTVAR) | BOTH_MASK
                        push!(ld.cp_lstack, p)              # TrailCyclic(p)
                        push!(ld.cp_lstack, f)              # TrailCyclic(from)
                    end
                else                                        # (no COPY_MARKED) setVar(*to)
                    ld.gstack[t] = word(0)
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
# or `Int(GLOBAL_OVERFLOW)` (since L1f f1b).
"Copy the term at location `from` into the unbound global cell `to` (pl-copyterm.c `do_copy_term`): 1 or `Int(GLOBAL_OVERFLOW)`."
function do_copy_term_cells(
    ld::PL_local_data{T}, from::Int, to::Int, options::cp_options
)::Int where {T}
    k, w, p = _deref_loc(ld, from)
    k == DU_CELL && return 1                                # TAG_VAR: `to` stays a fresh variable
    if !(k == DU_ATTVAR || (k == DU_WORD && _is_gcompound(w)))  # TAG_ATTVAR, TAG_COMPOUND: break
        # an atomic: *to = *from
        nw = _value_word!(ld, w)                            # (an indirect's word: shared; a slot's
        ld.gstack[to] = nw                                  #  side value its own word, f3-1)
        return 1
    end
    src = p > 0 ? p : from                                  # the location holding the compound's word
    fl = options.flags
    rc = if (fl & COPY_SHARE) != 0
        mark_for_copy_cells(ld, src, fl)
    else
        mark_for_duplicate_cells(ld, src, fl)
    end
    if rc != 1
        cp_unmark_cells(ld, src, fl)
        return rc
    end
    rc2 = copy_term_cells(ld, src, to, fl)                  # initCyclicCopy: nothing to do
    exitCyclicCopy_cells(ld, fl)
    cp_unmark_cells(ld, src, fl)
    return Int(rc2)
end

# ── the built-ins ───────────────────────────────────────────────────────────────────────────────
# PORT: pl-copyterm.c copy_term_refs
# DIVERGES: on the CELLS (L1d step 6): a fresh global cell, `to` its `makeRefG`, as upstream; no `vars`
# (copy_term/4). The loop is upstream's (since L1f f1b): a copy that does not fit is discarded with its
# foreign frame and `makeMoreStackSpace` asked — which here raises the overflow (see there).
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
    copy_term_refs(ld, A1, copy, cp_options(COPY_SHARE | COPY_ATTRS)) || return FFALSE
    return PL_unify(ld, copy, A2) ? FTRUE : FFALSE
end

# PORT: pl-copyterm.c copy_term_nat as pl_copy_term_nat2_va
# (PRED_IMPL("copy_term_nat", 2, copy_term_nat, 0)): `COPY_SHARE`, an attvar copied as a variable.
"`copy_term_nat(+In, -Out)`: `copy_term/2` without attributes."
function pl_copy_term_nat2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    copy = PL_new_term_ref(ld)                              # (upstream has no atomic shortcut here)
    copy_term_refs(ld, A1, copy, cp_options(COPY_SHARE)) || return FFALSE
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
    copy_term_refs(ld, A1, copy, cp_options(COPY_ATTRS)) || return FFALSE
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
