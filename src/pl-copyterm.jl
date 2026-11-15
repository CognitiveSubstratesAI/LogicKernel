# UPSTREAM: swipl-devel src/pl-copyterm.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2026, University of Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# PIN1 ledger (V10.1.20): structure only, d755bdc4 — pl-copyterm.c: cell-tag access behind pl-data.h macros, no change of value, order, error or side effect.
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
# `copy_term/4` (`COPY_MARKED`, `mark_vars`, `COPYING_ATTVAR`, `MC_WALK_COPY`) and `size_abstract_term/3` (`COPY_ABSTRACT`,
# `cp_options.abstract`, the depth agenda) are PRIMS-B2's. Later: `copy_term_nat/4` and `$fast_record/2`,
# `$fast_recorded/2` (testing bindings). The fast heap terms (`term_to_fastheap`,
# R2 EV1) are the term's record. `duplicate_term`'s
# `nshare`/`share` (the compounds kept shared) are `nb_setarg/3`'s (src/pl-prims.jl).

# PORT: pl-copyterm.c COPY_SHARE
"Share ground terms (pl-copyterm.c `COPY_SHARE`)."
const COPY_SHARE = 0x01
# PORT: pl-copyterm.c COPY_ATTRS
"Copy attributes (pl-copyterm.c `COPY_ATTRS`)."
const COPY_ATTRS = 0x02

# PORT: pl-copyterm.c COPY_ABSTRACT
"Abstract compounds beyond `cp_options.abstract` (pl-copyterm.c `COPY_ABSTRACT`; `size_abstract_term/3`)."
const COPY_ABSTRACT = 0x04
# PORT: pl-copyterm.c COPY_MARKED
"Only copy the marked variables (pl-copyterm.c `COPY_MARKED`; `copy_term/4`)."
const COPY_MARKED = 0x08
# PORT: pl-copyterm.c COPYING_ATTVAR
"Set while `mark_for_copy` closes a compound met inside an attributed variable's attributes (pl-copyterm.c `COPYING_ATTVAR`)."
const COPYING_ATTVAR = 0x10

# PORT: pl-copyterm.c cp_options
# DIVERGES: `abstract` is the last field (upstream's first), `(size_t)-1` is `typemax(Int)`; `share` is the first of
# `nshare` consecutive term references whose compounds `duplicate_term` keeps shared.
"The options of a copy (pl-copyterm.c `cp_options`): its `flags` (`COPY_*`), the `nshare` terms at `share`, and the `abstract` budget."
struct cp_options
    flags::Int
    nshare::Int
    share::Int
    abstract::Int
end
cp_options(flags::Integer) = cp_options(Int(flags), 0, 0, typemax(Int))
cp_options(flags::Integer, nshare::Integer, share::Integer) =
    cp_options(Int(flags), Int(nshare), Int(share), typemax(Int))

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

# PORT: pl-copyterm.c mark_vars
# DIVERGES: on locations: the walk is `cell_agenda` over the cells (the slot of `t` is the start location), a variable
# cell's marks are its side-vector bits (see the section header), an attributed variable's are in its word, as upstream.
# A compound word met in a SLOT (only the start, a term reference's own word) is not marked visited: nothing refers back
# to a slot, so it is met once, and the second pass descends from it unconditionally. The agenda cannot refuse, so
# `MEMORY_OVERFLOW` never happens: returns true.
"Mark (`set`) or unmark the variables of the term `t` references for `copy_term/4`: `set_copy` on each (pl-copyterm.c `mark_vars`): true."
function mark_vars(ld::PL_local_data{T}, t::term_t, set::Bool)::Bool where {T}
    a = ld.walk_agenda
    start = -(t + 1)                                        # p = valTermRef(t)
    initCellAgenda!(a, 1, start)
    while true                                              # the first pass
        q = nextCellAgendaNoDeRef!(a)
        q == 0 && break
        k, w, p = _deref_loc(ld, q)
        if k == DU_ATTVAR                                   # TAG_ATTVAR: set_copy / clear_marks of its word
            ld.gstack[p] = set ? (w & ~MARK_MASK) | FIRST_MASK : w & ~BOTH_MASK
        elseif k == DU_CELL                                 # TAG_VAR: the side vector's bits
            m = _cp_vm(ld, p)
            _cp_vm!(ld, p, set ? (m & ~_CPV_MARK) | _CPV_FIRST : m & ~_CPV_BOTH)
        elseif k == DU_WORD && _is_gcompound(w)             # TAG_COMPOUND
            if (w & BOTH_MASK) == 0                         # !visited(*p)
                p != 0 && (ld.gstack[p] = w | MARK_MASK)    # set_visited(*p)
                c = valPtr(w)
                pushWorkCellAgenda!(a, arityFunctor(ld.functors, ld.gstack[c]), c + 1)
            end
        end
    end
    clearCellAgenda!(a)                                     # clearTermAgenda
    initCellAgenda!(a, 1, start)
    while true                                              # the second pass (rc == true: the variables stay)
        q = nextCellAgendaNoDeRef!(a)
        q == 0 && break
        k, w, p = _deref_loc(ld, q)
        if k == DU_WORD && _is_gcompound(w)                 # TAG_COMPOUND
            if p == 0 || (w & BOTH_MASK) != 0               # visited(*p) (a slot's word was not marked)
                p != 0 && (ld.gstack[p] = w & ~BOTH_MASK)   # clear_marks(*p)
                c = valPtr(w)
                pushWorkCellAgenda!(a, arityFunctor(ld.functors, ld.gstack[c]), c + 1)
            end
        end
    end
    clearCellAgenda!(a)
    return true
end

# PORT: pl-copyterm.c must_copy
"Whether the marks `w` carries say `FIRST` only (pl-copyterm.c `must_copy`; `is_ground` is the same test on a functor word)."
@inline _cp_must_copy(w::word)::Bool = (w & BOTH_MASK) == FIRST_MASK

# PORT: pl-copyterm.c can_share as can_share_cells
# DIVERGES: positions; `flags` for upstream's `options` (only `COPY_MARKED` and `COPYING_ATTVAR` are read). A virgin
# variable cell's marks are its side-vector bits, an attributed variable's are in its word.
"Whether the argument cell at global position `p` can be shared by a copy (pl-copyterm.c)."
function can_share_cells(ld::PL_local_data, p::Int, flags::Int)::Bool
    c = ld.gstack[p]
    while isRef(c)                                          # TAG_REFERENCE
        p = unRef(c)
        c = ld.gstack[p]
    end
    if isVar(c)                                             # TAG_VAR
        return (flags & COPY_MARKED) != 0 && (_cp_vm(ld, p) & _CPV_BOTH) == 0 && (flags & COPYING_ATTVAR) == 0
    elseif isAttVar(c)                                      # TAG_ATTVAR
        return (flags & COPY_MARKED) != 0 && (c & BOTH_MASK) == 0 && (flags & COPYING_ATTVAR) == 0
    end
    _is_gcompound(c) && return (ld.gstack[valPtr(c)] & BOTH_MASK) == FIRST_MASK   # is_ground
    return true
end

# PORT: pl-copyterm.c update_ground as update_ground_cells
"Mark the compound whose word is at location `l` ground when every argument can be shared, `flags` the options' (pl-copyterm.c)."
function update_ground_cells(ld::PL_local_data, l::Int, flags::Int)::Nothing
    q = valPtr(_cp_word(ld, l))
    f = ld.gstack[q]
    for a in (q + arityFunctor(ld.functors, f)):-1:(q + 1)
        can_share_cells(ld, a, flags) || return nothing
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

# PORT: pl-copyterm.c MC_MASK MC_WALK_REF MC_WALK_COPY
"The mode bits of `mark_for_copy`'s walk (pl-copyterm.c): `MC_WALK_REF` (below a reference or an attvar), `MC_WALK_COPY` (inside an attvar's attributes)."
const MC_MASK = 0x3
const MC_WALK_REF = 0x1
const MC_WALK_COPY = 0x2

# PORT: pl-copyterm.c must_copy_attvar
"Whether the marking walks into the attributes of the attributed variable with word `w` in walk mode `mode` (pl-copyterm.c `must_copy_attvar`)."
@inline function must_copy_attvar(w::word, flags::Int, mode::Int)::Bool
    if (flags & (COPY_ATTRS | COPY_MARKED)) != 0
        if (flags & COPY_MARKED) != 0
            (mode & MC_WALK_COPY) != 0 && return true
            return _cp_must_copy(w) && (flags & COPY_ATTRS) != 0
        else
            return true
        end
    else
        return false
    end
end

# PORT: pl-copyterm.c mark_for_copy as mark_for_copy_cells
# DIVERGES: on locations, the stack `ld.cp_stack` of `(loc << 2) | mode` (upstream's `MC_TAG`). An attributed
# variable's marks are in its word, as upstream (its tag survives them). As upstream, a compound is dispatched again
# after `update_ground` (its functor visited once → shared). Returns 1.
"Mark the term at location `start` for `copy_term` (pl-copyterm.c `mark_for_copy`): 1."
function mark_for_copy_cells(ld::PL_local_data{T}, start::Int, flags::Int)::Int where {T}
    stack = ld.cp_stack
    base = length(stack)
    p = start
    mode = 0
    while true
        c = _cp_word(ld, p)                                 # switch(tag(*p))
        copy_always = (flags & COPY_MARKED) == 0 || (mode & MC_WALK_COPY) != 0   # COPY_ALWAYS
        if isRef(c)                                         # TAG_REFERENCE
            push!(stack, (p << 2) | mode)
            mode |= MC_WALK_REF
            p = unRef(c)                                    # deRef(p)
            while isRef(ld.gstack[p])
                p = unRef(ld.gstack[p])
            end
            continue
        elseif isAttVar(c) && must_copy_attvar(c, flags, mode)   # TAG_ATTVAR
            push!(stack, (p << 2) | mode)
            mode |= MC_WALK_REF | MC_WALK_COPY
            p = valPtr(c & ~BOTH_MASK)                      # p = valPAttVar(*p & ~BOTH_MASK)
            continue
        elseif isAttVar(c)                                  # TAG_ATTVAR → TAG_VAR: marks in the word
            if (c & BOTH_MASK) == 0 && copy_always          # virgin && COPY_ALWAYS
                ld.gstack[p] = c | MARK_MASK
            elseif (c & BOTH_MASK) == MARK_MASK             # visited_once
                ld.gstack[p] = c | BOTH_MASK
            elseif _cp_must_copy(c)                         # must_copy
                ld.gstack[p] = (c & ~BOTH_MASK) | MARK_MASK
            end
        elseif isVar(c)                                     # TAG_VAR
            m = _cp_vm(ld, p)
            if (m & _CPV_BOTH) == 0 && copy_always          # virgin && COPY_ALWAYS
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
                    push!(stack, (p << 2) | mode)
                    mode &= ~MC_WALK_REF
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
        while (mode & MC_WALK_REF) != 0
            e = pop!(stack)
            p, mode = e >> 2, e & MC_MASK
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
            fl = (mode & MC_WALK_COPY) != 0 ? flags | COPYING_ATTVAR : flags   # opts.flags |= COPYING_ATTVAR
            e = pop!(stack)
            p, mode = e >> 2, e & MC_MASK
            update_ground_cells(ld, p, fl)
        end
    end
end

# PORT: pl-copyterm.c share_for_duplicate as share_for_duplicate_cells
# DIVERGES: `c` is the position of the compound's functor cell; the shared terms are compound words in
# term references (`may_share_in_duplicate`), read from the slots.
"Whether the compound at functor position `c` is one of the `options.nshare` terms to keep shared (pl-copyterm.c)."
function share_for_duplicate_cells(ld::PL_local_data, c::Int, options::cp_options)::Bool
    for i in 0:(options.nshare - 1)
        w = ld.slots[options.share + i + 1]                 # Word p = valTermRef(options->share+i)
        _is_gcompound(w) && valPtr(w) == c && return true   # t == valueTerm(*p)
    end
    return false
end

# PORT: pl-copyterm.c mark_for_duplicate as mark_for_duplicate_cells
# DIVERGES: on locations, the one-sided cell agenda; the 3-argument form is `duplicate_term/2`'s
# (`nshare` 0). An attributed variable's marks are in its word, as upstream.
"Mark the term at location `l` for `duplicate_term` (pl-copyterm.c `mark_for_duplicate`): 1."
mark_for_duplicate_cells(ld::PL_local_data{T}, l::Int, flags::Int) where {T} =
    mark_for_duplicate_cells(ld, l, flags, cp_options(flags))

"`mark_for_duplicate_cells` with the `options` of the copy: a term of `options.share` is marked ground, so it is shared (pl-copyterm.c)."
function mark_for_duplicate_cells(
    ld::PL_local_data{T}, l::Int, flags::Int, options::cp_options
)::Int where {T}
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
            if (f & BOTH_MASK) == 0                         # virgin(t->definition)
                if options.nshare != 0 && share_for_duplicate_cells(ld, c, options)
                    ld.gstack[c] = f | FIRST_MASK           # set_ground(t->definition)
                    continue
                end
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
# variable's are in its word, as upstream.
"Clear the copy marks of the term at location `l` (pl-copyterm.c `cp_unmark`)."
function cp_unmark_cells(ld::PL_local_data{T}, l::Int, flags::Int)::Nothing where {T}
    a = ld.walk_agenda
    initCellAgenda!(a, 1, l)
    while true
        q = nextCellAgendaNoDeRef!(a)
        q == 0 && break
        k, w, p = _deref_loc(ld, q)
        while k == DU_ATTVAR && (flags & COPY_ATTRS) != 0   # TAG_ATTVAR, COPY_ATTRS:
            (flags & COPY_MARKED) != 0 && (ld.gstack[p] = w & ~BOTH_MASK)   # COPY_MARKED: *p &= ~BOTH_MASK
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
# DIVERGES: on locations, the two-sided cell agenda with depth (`cell_agendaLRD`, upstream's term_agendaLRD);
# `abstract` is upstream's `options->abstract` (`typemax(Int)`: no limit; `aleft`); `to` is always a global position; a copy's cell holding VAR_MARK is an unbound cell
# with the side-vector bit (also under an attributed variable's forwarded word, without COPY_ATTRS).
# `*to = makeRefG(from)` (COPY_MARKED, COPY_ABSTRACT) is `makeRefG(f)`: `f` is a global position there (the
# copy of an unmarked variable is the original cell; the start of `copy_term/4` is a compound, never a variable).
# A compound's cells, and a copied attvar's (`alloc_attvar`), are `allocGlobalNoShift`'s:
# `GLOBAL_OVERFLOW` when they pass the limit (since L1f f1b), as upstream's.
"Copy the marked term at location `from` into the unbound global cell `to` (pl-copyterm.c `copy_term`): `BOOLEX_TRUE` or `GLOBAL_OVERFLOW`."
function copy_term_cells(
    ld::PL_local_data{T}, from::Int, to::Int, flags::Int, abstract::Int
)::boolex_t where {T}
    a = ld.cp_agenda
    aleft = typemax(Int)                                    # size_t aleft = (size_t)-1
    initCellAgendaLRD!(a, 1, from, to, 0)
    while true
        found, f, t = nextCellAgendaLRD!(a)
        found || break
        if a.depth == 1                                     # if ( agenda.work.depth == 1 )
            aleft = abstract                                #   aleft = options->abstract
        end
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
                elseif (flags & COPY_ABSTRACT) != 0
                    ld.gstack[t] = makeRefG(f)              # *to = makeRefG(from)
                elseif (_cp_vm(ld, f) & _CPV_BOTH) == 0     # virgin(*from): copy_term/4
                    ld.gstack[t] = makeRefG(f)              # *to = makeRefG(from)
                end                                         # else setVar(*to), done above
            elseif isAttVar(c)                              # TAG_ATTVAR
                p = valPtr(c & ~BOTH_MASK)                  # p = valPAttVar(*from & ~BOTH_MASK)
                if (flags & COPY_ATTRS) != 0
                    if isAttVar(ld.gstack[p])               # already copied
                        ld.gstack[t] = makeRefG(p)
                        break
                    end
                    if (flags & COPY_MARKED) == 0 || _cp_must_copy(c)   # isoff(COPY_MARKED) || must_copy(*from)
                        attr = alloc_attvar(ld)
                        if attr == 0                        # rc = GLOBAL_OVERFLOW; goto out
                            clearCellAgendaLRD!(a)
                            return GLOBAL_OVERFLOW
                        end
                        push!(ld.cp_lstack, p)              # TrailCyclic(p)
                        push!(ld.cp_lstack, f)              # TrailCyclic(from)
                        ld.gstack[f] = consPtr(attr, STG_GLOBAL | TAG_ATTVAR)
                        ld.gstack[t] = makeRefG(attr)
                        f = p                               # from = p; to = &attr[1]; goto again
                        t = attr + 1
                        continue
                    else
                        ld.gstack[t] = makeRefG(f)          # *to = makeRefG(from): copy_term/4
                    end
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
                elseif (flags & COPY_MARKED) != 0
                    ld.gstack[t] = makeRefG(f)              # *to = makeRefG(from): copy_term/4
                else                                        # setVar(*to)
                    ld.gstack[t] = word(0)
                end
            elseif _is_gcompound(c)                         # TAG_COMPOUND
                ff = valPtr(c)
                fd = ld.gstack[ff]
                if aleft == 0                               # abstracted: setVar(*to); continue
                    ld.gstack[t] = word(0)
                    break
                elseif aleft != typemax(Int)
                    aleft -= 1
                end
                if isRef(fd)                                # copied already (forwarded)
                    ld.gstack[t] = consPtr(unRef(fd), TAG_COMPOUND | STG_GLOBAL)
                elseif (fd & BOTH_MASK) == FIRST_MASK       # is_ground: shared
                    ld.gstack[t] = c
                else
                    arity = arityFunctor(ld.functors, fd)
                    ft = allocGlobalNoShift(ld, arity + 1)
                    if ft == 0                              # rc = GLOBAL_OVERFLOW; goto out
                        clearCellAgendaLRD!(a)
                        return GLOBAL_OVERFLOW
                    end
                    ld.gstack[ft] = fd & ~BOTH_MASK
                    if (fd & BOTH_MASK) == BOTH_MASK        # shared: forward the original
                        ld.gstack[ff] = makeRefG(ft)
                        push!(ld.cp_lstack, ff)             # TrailCyclic(&ff->definition)
                    end
                    ld.gstack[t] = consPtr(ft, TAG_COMPOUND | STG_GLOBAL)
                    pushWorkCellAgendaLRD!(a, arity, ff, ft, 1)
                end
            else                                            # an atomic word (an indirect shared)
                ld.gstack[t] = c
            end
            break
        end
    end
    clearCellAgendaLRD!(a)
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
    if (fl & COPY_SHARE) != 0
        rc = mark_for_copy_cells(ld, src, fl)
        if rc != 1
            cp_unmark_cells(ld, src, fl)
            return rc
        end
    elseif (fl & COPY_ABSTRACT) == 0                        # else if ( isoff(options, COPY_ABSTRACT) ): no marks
        rc = mark_for_duplicate_cells(ld, src, fl, options)
        if rc != 1
            cp_unmark_cells(ld, src, fl)
            return rc
        end
    end
    rc2 = copy_term_cells(ld, src, to, fl, options.abstract)   # initCyclicCopy: nothing to do
    exitCyclicCopy_cells(ld, fl)
    cp_unmark_cells(ld, src, fl)
    return Int(rc2)
end

# ── the built-ins ───────────────────────────────────────────────────────────────────────────────
# ORIGINAL: `copy_term_refs`' `vars` is upstream's term_t 0 (NULL) when absent; term references start at 0 here.
"The `vars` argument of `copy_term_refs`: no variables to mark (upstream's `0`)."
const _CP_NO_VARS = -1

# PORT: pl-copyterm.c copy_term_refs
# DIVERGES: on the CELLS (L1d step 6): a fresh global cell, `to` its `makeRefG`, as upstream. `vars` is upstream's, the
# term reference whose variables `copy_term/4` marks to copy (`mark_vars`); `_CP_NO_VARS` is upstream's `0` (term
# references start at 0 here). `mark_vars` cannot fail (its agenda is a vector), so upstream's `PL_no_memory()` return is
# not written. The loop is upstream's (since L1f f1b): a copy that does not fit is discarded with its
# foreign frame and `makeMoreStackSpace` asked — which here raises the overflow (see there).
"Make term reference `to` hold a copy of the term `from` references, only the variables `vars` references marked when `vars` is given; false, the overflow raised, when it does not fit (pl-copyterm.c)."
function copy_term_refs(
    ld::PL_local_data{T}, from::term_t, to::term_t, vars::term_t, options::cp_options
)::Bool where {T}
    while true
        fid = PL_open_foreign_frame(ld)
        ensureGlobalSpace(ld, 1) || (PL_close_foreign_frame(ld, fid); return false)
        dest = allocGlobalCells!(ld, 1)                     # dest = allocGlobal(1); setVar(*dest)
        ld.slots[to + 1] = makeRefG(dest)                   # *valTermRef(to) = makeRefG(dest)
        if vars != _CP_NO_VARS                              # if ( vars )
            mark_vars(ld, vars, true)                       # (cannot fail)
        end
        rc = do_copy_term_cells(ld, -(from + 1), dest, options)
        if rc < 0                                           # no space for copy
            PL_discard_foreign_frame(ld, fid)
            _slot_new_var!(ld, to + 1)                      # PL_put_variable(to): gc consistency
            if vars != _CP_NO_VARS
                mark_vars(ld, vars, false)
            end
            makeMoreStackSpace(ld, GLOBAL_OVERFLOW, ALLOW_SHIFT) || return false
        else
            PL_close_foreign_frame(ld, fid)
            return true
        end
    end
end

# PORT: pl-copyterm.c copy_term_refs
"`copy_term_refs` without `vars` (every caller but `copy_term/4`)."
copy_term_refs(
    ld::PL_local_data{T}, from::term_t, to::term_t, options::cp_options
)::Bool where {T} = copy_term_refs(ld, from, to, _CP_NO_VARS, options)

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

# PORT: pl-copyterm.c duplicate_term
# (the C function pl-gvar.c's setval_duplicate and the predicate both call)
# The 3-argument form is `duplicate_term/2`'s and `setval_duplicate`'s (`nshare` 0: the whole term is copied); the
# 5-argument form with `nshare`/`share` follows (SETARG, `nb_setarg/3`).
"`duplicate_term(ld, in, copy)`: `copy` becomes a copy of `in` that shares no compound with it, attributes copied (pl-copyterm.c)."
function duplicate_term(ld::PL_local_data{T}, in::term_t, copy::term_t)::Bool where {T}
    return copy_term_refs(ld, in, copy, cp_options(COPY_ATTRS))
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
    duplicate_term(ld, A1, copy) || return FFALSE
    return PL_unify(ld, copy, A2) ? FTRUE : FFALSE
end

# PORT: pl-copyterm.c duplicate_term
# DIVERGES: none beyond `copy_term_refs`'s; `share` is the first of `nshare` consecutive term references.
"Make `copy` a duplicate of `in` that shares no compound with it, except the `nshare` compounds at `share` (pl-copyterm.c)."
function duplicate_term(
    ld::PL_local_data{T}, in::term_t, copy::term_t, nshare::Int, share::term_t
)::Bool where {T}
    return copy_term_refs(ld, in, copy, cp_options(COPY_ATTRS, nshare, share))
end

# ── fast heap terms (pl-copyterm.c; EV1's event closures) ───────────────────────────────────────────────
# PORT: pl-copyterm.c term_to_fastheap
# DIVERGES: the copy is the term's `record` (src/pl-rec.jl `compileTermToHeap`: the variables become fresh at each
# `put_fastheap`), where upstream copies the duplicate's cells and registers its atoms; `nothing` for upstream's NULL
# (the record's building raised). Representation only: see `fastheap_term`.
"Copy the term `t` off the stacks (pl-copyterm.c): a `fastheap_term` that `put_fastheap` copies back, or `nothing`."
function term_to_fastheap(
    ld::PL_local_data{T}, t::term_t
)::Union{Nothing, fastheap_term{T}} where {T}
    r = compileTermToHeap(ld, t)
    return fastheap_term{T}(r.gsize, r.nvars, r.code, r.values)
end

# PORT: pl-copyterm.c free_fastheap
# DIVERGES: nothing to free (Julia's garbage collector; upstream unregisters the atoms of the cells).
"Free a `fastheap_term` (pl-copyterm.c)."
free_fastheap(::fastheap_term)::Nothing = nothing

# PORT: pl-copyterm.c put_fastheap
# DIVERGES: `copyRecordToGlobal` of the term's record into `t`, where upstream copies the cells to `gTop`.
"Make term reference `t` hold a fresh copy of the fast heap term `fht` (pl-copyterm.c); false when it does not fit."
function put_fastheap(
    ld::PL_local_data{T}, fht::fastheap_term{T}, t::term_t
)::Bool where {T}
    return copyRecordToGlobal(ld, t, record{T}(fht.gsize, fht.nvars, fht.code, fht.values))
end

# PORT: pl-copyterm.c copy_term as pl_copy_term4_va
# (PRED_IMPL("copy_term", 4, copy_term, 0)): `copy_term_4(A1, A2, A3, A4, COPY_ATTRS)`.
# REFUSED BY NAME (PRIMS-B): the copy is `copy_term_refs(Vs0-T0, Copy, Vs0, COPY_SHARE|COPY_MARKED|COPY_ATTRS)`, which
# first runs `mark_vars` (pl-copyterm.c) over `Vs0` and has `mark_for_copy`, `do_copy_term` and `copy_term_refs` read
# `COPY_MARKED`, `COPYING_ATTVAR` and `MC_WALK_COPY`: the copy of only the marked variables. The kernel's copy
# (`copy_term_refs`, above) has none of them; the owner row is docs/r2_owners.tsv's.
"`copy_term(+VarsIn, +Term, -VarsOut, -Copy)`: REFUSED (`NotPortedError`): needs pl-copyterm.c's `mark_vars` and `COPY_MARKED`."
function pl_copy_term4_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    throw(
        NotPortedError{T}(
            mk_sym(T, :copy_term), "copy_term/4 needs mark_vars and COPY_MARKED (pl-copyterm.c)", "PRIMS-B"
        )
    )
end

# PORT: pl-copyterm.c size_abstract_term as pl_size_abstract_term3_va
# (PRED_IMPL("size_abstract_term", 3, size_abstract_term, 0)): `PL_get_size_ex(A1, &abstract)` first, as upstream, so a
# bad size raises its error here too.
# REFUSED BY NAME (PRIMS-B): the abstraction is `size_abstract_term(A2, copy, abstract)`, `copy_term_refs` with
# `COPY_ATTRS|COPY_ABSTRACT` and the size budget `cp_options.abstract` that `do_copy_term` spends (`aleft`) and
# replaces the compounds beyond it by variables with. The kernel's `cp_options` has no `abstract` field.
"`size_abstract_term(+Size, +Term, -Abstract)`: REFUSED (`NotPortedError`) after `Size` is checked: needs pl-copyterm.c's `size_abstract_term` and `COPY_ABSTRACT`."
function pl_size_abstract_term3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    abstract = PL_get_size_ex(ld, A1)
    abstract === nothing && return FFALSE                   # the error is raised

    throw(
        NotPortedError{T}(
            mk_sym(T, :size_abstract_term),
            "size_abstract_term/3 needs size_abstract_term and COPY_ABSTRACT (pl-copyterm.c)",
            "PRIMS-B"
        )
    )
end

# PORT: pl-copyterm.c BeginPredDefs as PL_predicates_from_copyterm
# DIVERGES: the ported entries and the two refused by name (`copy_term/4`, `size_abstract_term/3`: PRIMS-B); upstream's
# table also has `copy_term_nat/4`, `$fast_record/2`, `$fast_recorded/2`.
"pl-copyterm.c's registration table (`BeginPredDefs(copyterm)`): the ported entries and the two refused ones."
const PL_predicates_from_copyterm = (
    PL_extension("copy_term", 2, pl_copy_term2_va, PL_FA_VARARGS | PL_FA_ISO),
    PL_extension("copy_term", 4, pl_copy_term4_va, PL_FA_VARARGS),                    # (PRIMS-B: refused)
    PL_extension("duplicate_term", 2, pl_duplicate_term2_va, PL_FA_VARARGS),
    PL_extension("copy_term_nat", 2, pl_copy_term_nat2_va, PL_FA_VARARGS),
    PL_extension("size_abstract_term", 3, pl_size_abstract_term3_va, PL_FA_VARARGS)
)
