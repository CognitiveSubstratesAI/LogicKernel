# UPSTREAM: swipl-devel src/pl-fli.c @ 8e1bc1110be4
# UPSTREAM: swipl-devel src/pl-fli.h @ 8e1bc1110be4
# CLASS: code
# COPYRIGHT: Copyright (c)  1996-2026, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# THE TERM REFERENCES of SWI-Prolog's foreign language interface (pl-fli.c): a `term_t` is a
# position on the local stack (src/pl-incl.jl § the local stack), allocated at `lTop` inside the
# innermost foreign frame, which counts them. Since V5a2, the `PL_*` functions the first built-ins
# and the foreign call path use, under upstream's names, on `(ld, term_t)`.

# The check upstream's API entry points make (fli:535-548): a term reference is made inside a
# foreign frame newer than the running Prolog frame — never while a query's answer has been left
# without one (after `PL_next_solution` returned a deterministic last answer and was called again).
function _check_foreign_environment(ld::PL_local_data{T}, what::String)::Nothing where {T}
    env = ld.environment_frame
    if env != 0 && ld.fliframes[ld.fli_context].base <= ld.frames[env].base
        error(what * "(): No foreign environment")              # fatalError()
    end
    return nothing
end

# PORT: pl-fli.c PL_new_term_refs
# DIVERGES: `n` positions. Each new reference holds a fresh variable: `setVar` of a cell is a new
# variable key here (decision 2). `O_CHECK_TERM_REFS` is `O_DEBUG` only. The foreign-environment
# check is the API entry point's (`PL_new_term_refs`, fli:535-548), made here.
"`n` new term references, each holding a fresh variable; the first one, or 0 (pl-fli.c)."
function PL_new_term_refs(ld::PL_local_data{T}, n::Int)::Int where {T}
    _check_foreign_environment(ld, "PL_new_term_refs")
    if !ensureLocalSpace(ld, n)
        return 0
    end

    t = ld.lTop
    r = t                                       # consTermRef(t)

    p = allocGlobalCells!(ld, n)
    for i in 0:(n - 1)
        ld.slots[t + 1] = makeRefG(p + i)       # setVar(*t++): a global cell's reference (L1b C5)
        t += 1
    end
    ld.lTop = t
    fr = ld.fli_context
    ld.fliframes[fr].size += n

    return r
end

# PORT: pl-fli.c new_term_ref
# DIVERGES: the new reference holds a fresh variable (as `PL_new_term_refs`).
"A new term reference holding a fresh variable, without making room first (pl-fli.c)."
function new_term_ref(ld::PL_local_data{T})::Int where {T}
    t = ld.lTop
    r = t                                       # consTermRef(t)
    _slot_new_var!(ld, t + 1)                   # setVar(*t++)
    t += 1

    ld.lTop = t
    fr = ld.fli_context
    ld.fliframes[fr].size += 1

    return r
end

# PORT: pl-fli.c PL_new_term_ref
# DIVERGES: the foreign-environment check is the API entry point's (fli:544-549), made here.
"A new term reference holding a fresh variable, or 0 (pl-fli.c)."
function PL_new_term_ref(ld::PL_local_data{T})::Int where {T}
    _check_foreign_environment(ld, "PL_new_term_ref")
    if !ensureLocalSpace(ld, 1)
        return 0
    end

    return new_term_ref(ld)
end

# PORT: pl-fli.c PL_reset_term_refs
# DIVERGES: lowering `lTop` drops the records above it (decision 3; there are none above a term
# reference of the innermost foreign frame).
"Free term reference `r` and every one allocated after it (pl-fli.c)."
function PL_reset_term_refs(ld::PL_local_data{T}, r::Int)::Nothing where {T}
    fr = ld.fli_context
    f = ld.fliframes[fr]

    lowerLTop!(ld, r)                           # lTop = (LocalFrame) valTermRef(r);
    f.size = ld.lTop - (f.base + SIZEOF_FLIFRAME)
    @assert f.size >= 0 "PL_reset_term_refs: below its foreign frame"   # DEBUG(0, …)
    return nothing
end

# PORT: pl-fli.c PL_copy_term_ref
# DIVERGES: no `globalizeTermRef`. Upstream moves an unbound variable out of a local cell, which
# nothing may point into; a keyed variable lives in no cell (decision 2). `CHK_SECURE` is
# `O_DEBUG` only.
"A new term reference to the term `from` references; or 0 (pl-fli.c)."
function PL_copy_term_ref(ld::PL_local_data{T}, from::Int)::Int where {T}
    if !ensureLocalSpace(ld, 1)
        return 0
    end

    t = ld.lTop
    r = t                                       # consTermRef(t)
    _slot_link!(ld, t + 1, from + 1)                # *t = linkValI(valHandleP(from))
    ld.lTop = t + 1
    fr = ld.fli_context
    ld.fliframes[fr].size += 1

    return r
end

# PORT: pl-fli.c PL_cons_list
# DIVERGES: no global space to ensure, so it cannot fail; on the CELLS (L1e e3): three cells at gTop,
# `bindConsVal` as `_cell_link!` (linkValI from the head's and tail's slots).
"Make term reference `l` hold the list cell of the terms `head` and `tail` reference (pl-fli.c)."
function PL_cons_list(
    ld::PL_local_data{T}, l::term_t, head::term_t, tail::term_t
)::Bool where {T}
    a = _alloc_compound!(ld, ld.functor_dot2, 2)            # a = allocGlobal(3); a[0] = FUNCTOR_dot2
    _cell_link!(ld, a + 1, head + 1)                        # bindConsVal(&a[1], valHandleP(head))
    _cell_link!(ld, a + 2, tail + 1)                        # bindConsVal(&a[2], valHandleP(tail))
    ld.slots[l + 1] = consPtr(a, TAG_COMPOUND | STG_GLOBAL) # setHandle(l, consPtr(a, …))
    return true
end

# PORT: pl-fli.c PL_unify_list
# DIVERGES: no global space to ensure; on the CELLS (L1e e3): an unbound cell bound (`bindConst`) to a new
# `'[|]'/2` compound at gTop, `h`/`t` its argument cells' references; a list word's arguments linked
# (`linkValI`); the boundary (DU_TERM) on terms, counted.
"Unify term reference `l` with a list cell, putting its head and tail into `h` and `t` (pl-fli.c)."
function PL_unify_list(
    ld::PL_local_data{T}, l::term_t, h::term_t, t::term_t
)::Bool where {T}
    k, w, q = _deref_loc(ld, -(l + 1))                      # p = valHandleP(l); deRef(p)
    if k == DU_CELL                                         # canBind(*p)
        a = _alloc_compound!(ld, ld.functor_dot2, 2)        # a[0] = FUNCTOR_dot2; setVar(a[1]), (a[2])
        ld.slots[h + 1] = makeRefG(a + 1)                   # setHandle(h, makeRefG(&a[1]))
        ld.slots[t + 1] = makeRefG(a + 2)                   # setHandle(t, makeRefG(&a[2]))
        _bind_const!(ld, q, consPtr(a, TAG_COMPOUND | STG_GLOBAL))   # bindConst(p, c)
        return true
    elseif _is_list_word(ld, k, w)                          # isList(*p)
        _slot_link_loc!(ld, h + 1, _deref_loc(ld, valPtr(w) + 1))    # setHandle(h, linkValI(a))
        _slot_link_loc!(ld, t + 1, _deref_loc(ld, valPtr(w) + 2))    # setHandle(t, linkValI(a+1))
        return true
    end
    k == DU_TERM || return false
    ld.cold_pairs += 1                                      # the boundary: on terms
    p = deRef(ld, slotValue(ld, l + 1))

    if canBind(p)
        k = allocGlobalCells!(ld, 2)
        a1, a2 = _cell_var(ld, k), _cell_var(ld, k + 1)
        c = mk_expr(T, T[mk_sym(T, LIST_CONS_NAME), a1, a2])
        setSlotValue!(ld, h + 1, a1)                            # setHandle(h, makeRefG(a))
        setSlotValue!(ld, t + 1, a2)

        Trail!(ld, var_key(p), c)                       # bindConst(p, c)
    elseif is_pair(p)                                   # isList(*p)
        setSlotValue!(ld, h + 1, linkValI(ld, child(p, 2)))
        setSlotValue!(ld, t + 1, linkValI(ld, child(p, 3)))
    else
        return false
    end

    return true
end

# PORT: pl-fli.c PL_unify_nil
"Unify term reference `l` with `[]` (pl-fli.c)."
PL_unify_nil(ld::PL_local_data{T}, l::term_t) where {T} = PL_unify_atom(ld, l, mk_nil(T))

# PORT: pl-fli.c PL_skip_list
# DIVERGES: returns `(type, length)` where upstream writes the length through `len`; on the WORDS (L1e e2:
# `skip_list_cells`, L1d step 9); a tail at the boundary — the whole list then walked on terms, counted in
# `cold_pairs`. NOT PORTED: `tail` (upstream unifies it with the list's tail): no caller here passes one.
"The type of the list term reference `list` holds — `PL_LIST`, `PL_PARTIAL_LIST`, `PL_CYCLIC_TERM`, `PL_NOT_A_LIST` — and its cells (pl-fli.c)."
function PL_skip_list(ld::PL_local_data{T}, list::term_t)::Tuple{Int, Int} where {T}
    length, k, w, _ = skip_list_cells(ld, -(list + 1))
    if k != DU_TERM
        k == DU_WORD && w == ld.atom_nil_w && return (PL_LIST, length)    # isNil(*tail)
        k == DU_CELL && return (PL_PARTIAL_LIST, length)                  # canBind(*tail)
        _is_list_word(ld, k, w) && return (PL_CYCLIC_TERM, length)        # isList(*tail)
        return (PL_NOT_A_LIST, length)
    end
    ld.cold_pairs += 1                                      # the boundary: on terms
    length, t = skip_list(ld, slotValue(ld, list + 1))

    if is_nil(t)
        return (PL_LIST, length)
    elseif kind(t) === VAR
        return (PL_PARTIAL_LIST, length)
    elseif is_pair(t)
        return (PL_CYCLIC_TERM, length)
    else
        return (PL_NOT_A_LIST, length)
    end
end

# PORT: pl-fli.c PL_unify_functor
# DIVERGES: the functor is its name and arity; no global space to ensure. An unbound term is bound
# to `name` of `arity` fresh variables, their keys in argument order.
"Unify term reference `t` with a term `name/arity` — binding it to one of fresh variables, or checking its functor (pl-fli.c)."
function PL_unify_functor(
    ld::PL_local_data{T}, t::term_t, name::T, arity::Int
)::Bool where {T}
    k, w, q = _deref_loc(ld, -(t + 1))                      # p = valHandleP(t); deRef(p) (L1e e3)
    if k != DU_TERM
        nw = _atom_word!(ld, name)                          # nameFunctor(f)
        if k == DU_CELL                                     # canBind(*p)
            if arity == 0
                _bind_const!(ld, q, nw)                     # bindConst(p, name)
            else                                            # *a = f; setVar(*++a)…
                a = _alloc_compound!(ld, lookupFunctorDef(ld.functors, nw, arity), arity)
                _bind_const!(ld, q, consPtr(a, TAG_COMPOUND | STG_GLOBAL))   # bindConst(p, to)
            end
            return true
        end
        arity == 0 && return k == DU_WORD && w == nw        # *p == nameFunctor(f)
        return k == DU_WORD && _is_gcompound(w) &&          # hasFunctor(*p, f)
               ld.gstack[valPtr(w)] == lookupFunctorDef(ld.functors, nw, arity)
    end
    ld.cold_pairs += 1                                      # the boundary: on terms
    p = deRef(ld, slotValue(ld, t + 1))

    if canBind(p)
        if arity != 0
            k = allocGlobalCells!(ld, arity)
            a = Vector{T}(undef, 1 + arity)
            a[1] = name
            for i in 1:arity
                a[i + 1] = _cell_var(ld, k + i - 1)    # setVar(a[i])
            end

            Trail!(ld, var_key(p), mk_expr(T, a))       # bindConst(p, to)
            return true
        else
            Trail!(ld, var_key(p), name)                # bindConst(p, name)
            return true
        end
    else
        if arity != 0
            return _hasFunctor(p, name, arity)
        else
            return kind(p) === SYM && sym_key(p) == sym_key(name)
        end
    end
end

# PORT: pl-fli.c PL_unify_compound
# DIVERGES: `f` is a functor WORD (`$expr/n` too); no global space to ensure. The boundary (DU_TERM)
# is unified on terms with the compound laid out, counted.
"Unify term reference `t` with a compound of functor word `f` — binding it to one of fresh arguments, or checking its functor (pl-fli.c)."
function PL_unify_compound(ld::PL_local_data{T}, t::term_t, f::word)::Bool where {T}
    k, w, q = _deref_loc(ld, -(t + 1))                      # p = valHandleP(t); deRef(p)
    if k == DU_CELL                                         # canBind(*p)
        a = _alloc_compound!(ld, f, arityFunctor(ld.functors, f))  # *a = f; setVar(*++a)…
        _bind_const!(ld, q, consPtr(a, TAG_COMPOUND | STG_GLOBAL))   # bindConst(p, to)
        return true
    elseif k == DU_TERM
        ld.cold_pairs += 1                                  # the boundary: on terms
        a = _alloc_compound!(ld, f, arityFunctor(ld.functors, f))
        return do_unify(ld, _loc_term(ld, k, w, q), _compound_term(ld, a)) == BOOLEX_TRUE
    end
    return k == DU_WORD && _is_gcompound(w) && ld.gstack[valPtr(w)] == f   # hasFunctor(*p, f)
end

# PORT: pl-fli.c PL_unify_arg_sz as PL_unify_arg
# DIVERGES: a compound whose head is no symbol has every child as an argument (see `_PL_get_arg`).
"Unify argument `index` (from 1) of the compound term reference `t` holds with the term `a` references (pl-fli.c)."
function PL_unify_arg(
    ld::PL_local_data{T}, index::Int, t::term_t, a::term_t
)::Bool where {T}
    k, x, _ = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t) (L1e e3: the cells)
    if k == DU_WORD && _is_gcompound(x)                     # isTerm(w)
        q = valPtr(x)
        0 < index <= arityFunctor(ld.functors, ld.gstack[q]) || return false   # index <= arity
        return unify_ptrs_cells(ld, q + index, -(a + 1))    # unify_ptrs(argTermP(w, index-1), valHandleP(arg))
    end
    k == DU_TERM || return false
    ld.cold_pairs += 1                                      # the boundary: on terms
    w = deRef(ld, slotValue(ld, t + 1))

    if isTerm(w)
        off, arity = _comp_shape(w)
        if index > 0 && index <= arity
            return unify_ptrs(ld, child(w, off + index - 1), slotValue(ld, a + 1))
        end
    end

    return false
end

# PORT: pl-fli.c PL_put_term
# DIVERGES: no `globalizeTermRef` (as `PL_copy_term_ref`), so it cannot fail; on the WORDS
# (`_slot_link!`, L1c) — a compound's word moved, not exported and copied back, and a value (the
# exception's ball, decision 1) kept a value, as upstream's frozen ball stays where it is.
"Make term reference `t1` reference the term `t2` references (pl-fli.c)."
function PL_put_term(ld::PL_local_data{T}, t1::Int, t2::Int)::Bool where {T}
    _slot_link!(ld, t1 + 1, t2 + 1)                 # setHandle(t1, linkValI(p2))
    return true
end

# PORT: pl-fli.h PL_put_variable
# DIVERGES: a slot holds no unbound word, so its fresh variable is a global cell (as `new_term_ref`'s).
"Make term reference `t` hold a fresh variable (pl-fli.h)."
function PL_put_variable(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    _slot_new_var!(ld, t + 1)                       # setVar(*valTermRef(t))
    return true
end

# PORT: pl-fli.h PL_put_atom
"Make term reference `t` hold the atom `a` (pl-fli.h)."
function PL_put_atom(ld::PL_local_data{T}, t::term_t, a::T)::Bool where {T}
    ld.slots[t + 1] = _atom_word!(ld, a)            # setHandle(t, a)
    return true
end

# PORT: pl-fli.c PL_put_nil
"Make term reference `l` hold `[]` (pl-fli.c)."
PL_put_nil(ld::PL_local_data{T}, l::term_t) where {T} = PL_put_atom(ld, l, mk_nil(T))

# PORT: pl-fli.h PL_put_int64
# DIVERGES: the integer's word as `PL_put_intptr` lays it (a tagged integer, or a value-table word
# under `_slot_store!`'s older-slot rule); it cannot fail (no `put_int64` allocation to refuse).
"Make term reference `t` hold the integer `i` (pl-fli.h)."
PL_put_int64(ld::PL_local_data{T}, t::term_t, i::Int) where {T} = PL_put_intptr(ld, t, i)

# PORT: pl-fli.c PL_put_integer
"Make term reference `t` hold the integer `i` (pl-fli.c)."
PL_put_integer(ld::PL_local_data{T}, t::term_t, i::Int) where {T} = PL_put_int64(ld, t, i)

# PORT: pl-fli.c _PL_put_number
# DIVERGES: the number is a `number` record; its word as `_slot_store!` lays a number (tagged, or
# a value-table word), so it cannot fail.
"Make term reference `t` hold the number `n` (pl-fli.c)."
function _PL_put_number(ld::PL_local_data{T}, t::term_t, n::number)::Bool where {T}
    setSlotValue!(ld, t + 1, put_number(T, n))      # setHandle(t, consInt(…)) / put_number(&w, n)
    return true
end

# PORT: pl-fli.c PL_cons_functor
# DIVERGES: the arguments are a typed `Vararg` of term references (upstream's `va_list`, read by
# `cons_functorv`), the functor a functor WORD; no global space to ensure, so it cannot fail. Each
# argument is laid in by `_cell_link!` (`bindConsVal`), a slot's side value through its word (f3b-1).
"Make term reference `h` hold a new compound of functor word `fd` whose arguments are the terms `a…` reference (pl-fli.c)."
function PL_cons_functor(
    ld::PL_local_data{T}, h::term_t, fd::word, a::Vararg{term_t, N}
)::Bool where {T, N}
    @assert arityFunctor(ld.functors, fd) == N                  # size_t arity = arityFunctor(fd)
    if N == 0
        ld.slots[h + 1] = nameFunctor(ld.functors, fd)          # setHandle(h, nameFunctor(fd))
        return true
    end
    p = _alloc_compound!(ld, fd, N)                             # a = t = gTop; gTop += 1+arity; *a = fd
    for i in 1:N
        _cell_link!(ld, p + i, a[i] + 1)                        # bindConsVal(++a, valHandleP(r))
    end
    ld.slots[h + 1] = consPtr(p, TAG_COMPOUND | STG_GLOBAL)     # setHandle(h, consPtr(t, …))
    return true
end

# PORT: pl-fli.c pushWordAsTermRef
# DIVERGES: the word is a DEREFERENCED location `(k, w, p)` (`_deref_loc`), where upstream passes a
# `Word` — a slot's own word has no global position here; `linkValNoG(p)` is `_slot_link_loc!`. The
# handles are TMP_PTR_SIZE consecutive references from `ld.tmp_h`, made by `emptyStacks!`.
"A temporary term reference holding the location `(k, w, p)`; release it with `popTermRef` (pl-fli.c)."
function pushWordAsTermRef(
    ld::PL_local_data{T}, loc::Tuple{UInt8, word, Int}
)::term_t where {T}
    i = ld.tmp_top                                  # int i = LD->tmp.top++
    ld.tmp_top += 1
    t = ld.tmp_h + i                                # term_t t = LD->tmp.h[i]
    @assert i < TMP_PTR_SIZE
    _slot_link_loc!(ld, t + 1, loc)                 # setHandle(t, linkValNoG(p))
    return t
end

# PORT: pl-fli.c popTermRef
# DIVERGES: `setVar` of the handle makes it reference its PERMANENT cell again, unbound (as
# `_reset_exception_slot!`): a fresh cell would be freed by the next `Undo!` under the handle.
"Release the last temporary term reference `pushWordAsTermRef` handed out (pl-fli.c)."
function popTermRef(ld::PL_local_data{T})::Nothing where {T}
    ld.tmp_top -= 1                                 # int i = --LD->tmp.top
    i = ld.tmp_top
    @assert i >= 0
    c = ld.tmp_cells + i
    ld.gstack[c] = word(0)                          # setVar(*valTermRef(LD->tmp.h[i]))
    ld.slots[ld.tmp_h + i + 1] = makeRefG(c)
    return nothing
end

# (untyped: an implementation's leaves may be of different concrete types under one term type)
"`p` is a compound `name/arity` (`hasFunctor`): a symbol head named `name` and `arity` arguments."
_hasFunctor(p, name, arity::Int) =
    kind(p) === EXPR && nchildren(p) == arity + 1 && kind(child(p, 1)) === SYM &&
    sym_key(child(p, 1)) == sym_key(name)

# PORT: pl-fli.c classify_exception_p
# `error(resource_error(_), _)` is `EXCEPT_RESOURCE` since upstream's fix 85d0cc2
# (SWI-Prolog/swipl-devel#1535, docs/upstream_reports.md #5); until it the test was for the ATOM
# `resource_error`, which nothing raises, and the stack overflow's error ranked as an ordinary one.
"The class of the ball `p` (pl-fli.c `classify_exception_p`)."
function classify_exception_p(ld::PL_local_data{T}, p::T)::except_class where {T}
    p = deRef(ld, p)
    if kind(p) === VAR
        return EXCEPT_NONE
    elseif kind(p) === SYM
        sym_key(p) == sym_key(mk_sym(T, :time_limit_exceeded)) && return EXCEPT_TIMEOUT
    elseif _hasFunctor(p, mk_sym(T, :error), 2)
        a = deRef(ld, child(p, 2))                          # p = argTermP(*p, 0)
        _hasFunctor(a, mk_sym(T, :resource_error), 1) && return EXCEPT_RESOURCE
        return EXCEPT_ERROR
    elseif _hasFunctor(p, mk_sym(T, :time_limit_exceeded), 1)
        return EXCEPT_TIMEOUT
    elseif _hasFunctor(p, mk_sym(T, :unwind), 1)
        a = deRef(ld, child(p, 2))
        if kind(a) === SYM
            sym_key(a) == sym_key(mk_sym(T, :abort)) && return EXCEPT_ABORT
        elseif _hasFunctor(a, mk_sym(T, :halt), 1)
            return EXCEPT_HALT
        elseif _hasFunctor(a, mk_sym(T, :thread_exit), 1)
            return EXCEPT_THREAD_EXIT
        end
        return EXCEPT_UNWIND
    end
    return EXCEPT_OTHER
end

# PORT: pl-fli.h classify_exception
"The class of the ball term reference `exception` holds, `EXCEPT_NONE` for none (pl-fli.h)."
function classify_exception(ld::PL_local_data{T}, exception::Int)::except_class where {T}
    exception == 0 && return EXCEPT_NONE
    k, w, p = _deref_loc(ld, -(exception + 1))      # valTermRef(exception); deRef (L1e e5: the words)
    k == DU_TERM || return classify_exception_cells(ld, k, w)
    ld.cold_pairs += 1                              # the boundary: on the term
    return classify_exception_p(ld, _loc_term(ld, k, w, p))
end

# PORT: pl-fli.c classify_exception_p as classify_exception_cells
# DIVERGES: on a dereferenced location's `(kind, word)` (L1e e5), the functors compared as words; an argument
# at the boundary read as its term (`classify_exception_p`), counted.
"The class of the exception the dereferenced `(k, w)` holds (pl-fli.c `classify_exception_p`)."
function classify_exception_cells(
    ld::PL_local_data{T}, k::UInt8, w::word
)::except_class where {T}
    k == DU_CELL && return EXCEPT_NONE                                  # isVar(*p)
    if k == DU_WORD && isAtomW(w)                                       # isTextAtom(*p)
        w == _atom_word!(ld, mk_sym(T, :time_limit_exceeded)) && return EXCEPT_TIMEOUT
    elseif k == DU_WORD && _is_gcompound(w)
        q = valPtr(w)
        f = ld.gstack[q]
        if f == lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :error)), 2)                                          # hasFunctor(*p, FUNCTOR_error2)
            ka, wa, pa = _deref_loc(ld, q + 1)                          # p = argTermP(*p, 0); deRef(p)
            if ka == DU_TERM
                ld.cold_pairs += 1
                return classify_exception_p(ld, _loc_term(ld, k, w, 0))
            end
            ka == DU_WORD && _is_gcompound(wa) &&
                ld.gstack[valPtr(wa)] == lookupFunctorDef(
                    ld.functors, _atom_word!(ld, mk_sym(T, :resource_error)), 1
                ) &&
                return EXCEPT_RESOURCE
            return EXCEPT_ERROR
        elseif f == lookupFunctorDef(
            ld.functors, _atom_word!(ld, mk_sym(T, :time_limit_exceeded)), 1
        )
            return EXCEPT_TIMEOUT
        elseif f == lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :unwind)), 1)
            ka, wa, pa = _deref_loc(ld, q + 1)
            if ka == DU_TERM
                ld.cold_pairs += 1
                return classify_exception_p(ld, _loc_term(ld, k, w, 0))
            end
            ka == DU_WORD && isAtomW(wa) && wa == _atom_word!(ld, mk_sym(T, :abort)) &&
                return EXCEPT_ABORT
            if ka == DU_WORD && _is_gcompound(wa)
                fa = ld.gstack[valPtr(wa)]
                fa == lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :halt)), 1) &&
                    return EXCEPT_HALT
                fa == lookupFunctorDef(
                    ld.functors, _atom_word!(ld, mk_sym(T, :thread_exit)), 1
                ) && return EXCEPT_THREAD_EXIT
            end
            return EXCEPT_UNWIND
        end
    end
    return EXCEPT_OTHER
end

# PORT: pl-fli.c PL_get_atom
# DIVERGES: returns the atom, or `nothing`, where upstream writes it through `a` and returns a Bool;
# on the WORDS (`valHandle(t)`, `_deref_loc`; L1d step 7b — the FLI readers the writer calls, L1e
# done early): an atom word its symbol (`_atom_value`); the boundary (a slot's side value, a
# keyed variable) read as its term, counted in `cold_pairs`.
"The atom term reference `t` holds — a text atom or a reserved symbol such as `[]` — or `nothing` (pl-fli.c)."
function PL_get_atom(ld::PL_local_data{T}, t::term_t)::Union{Nothing, T} where {T}
    k, w, p = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    if k == DU_WORD
        isAtomW(w) && return _atom_value(ld, w)             # isAtom(w)
    elseif k == DU_TERM                                     # the boundary: on the term
        ld.cold_pairs += 1
        v = deRef(ld, _loc_term(ld, k, w, p))
        kind(v) === SYM && return v
    end
    return nothing
end

# PORT: pl-fli.c PL_get_integer
# DIVERGES: returns the value, or `nothing`, where upstream writes it through `i`; on the WORDS (L1e e2):
# a tagged integer's value (`valInt(w)`); the boundary read as its term, counted in `cold_pairs`.
"The C `int` term reference `t` holds — a tagged integer in `int`'s range — or `nothing` (pl-fli.c)."
function PL_get_integer(ld::PL_local_data{T}, t::term_t)::Union{Nothing, Int} where {T}
    k, w, p = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    if k == DU_VALUE && isTaggedIntW(w)                     # isTaggedInt(w)
        val = valInt(w)
        (val > typemax(Int32) || val < typemin(Int32)) && return nothing
        return Int(val)
    end
    k == DU_TERM || return nothing
    ld.cold_pairs += 1                                      # the boundary: on the term
    w = deRef(ld, _loc_term(ld, k, w, p))
    if isTaggedInt(w)
        val = int64_value(w)
        (val > typemax(Int32) || val < typemin(Int32)) && return nothing
        return Int(val)
    end
    return nothing
end

# PORT: pl-fli.c PL_get_long
# DIVERGES: returns the value, or `nothing`, where upstream writes it through `i`; on the WORDS
# (`valHandle(t)`, `_deref_loc`, L1d step 7a): a tagged integer its value (a `long` is 64 bits: in
# range), a value-table integer that fits `Int64` (`get_int64`) its value; the boundary (a slot's side
# value, a keyed variable) read as its term, counted in `cold_pairs`.
"The C `long` term reference `t` holds — an integer in `Int64`'s range — or `nothing` (pl-fli.c)."
function PL_get_long(ld::PL_local_data{T}, t::term_t)::Union{Nothing, Int} where {T}
    k, w, p = _deref_loc(ld, -(t + 1))
    if k == DU_VALUE
        isTaggedIntW(w) && return Int(valInt(w))           # isTaggedInt(w)
        v = ld.vtable[valPtr(w)]
    elseif k == DU_TERM
        ld.cold_pairs += 1
        v = deRef(ld, _loc_term(ld, k, w, p))
    else
        return nothing
    end
    (isInteger(v) && integer_is_int64(v)) && return Int(int64_value(v))   # get_int64(w, &i64)
    return nothing
end

# PORT: pl-fli.c atom_to_bool
# DIVERGES: `nothing` for neither, where upstream returns -1.
"The Boolean atom `a` names — `true`/`on` or `false`/`off` — or `nothing` (pl-fli.c)."
function atom_to_bool(ld::PL_local_data{T}, a::T)::Union{Nothing, Bool} where {T}
    k = sym_key(a)
    (k == sym_key(mk_sym(T, Symbol("true"))) || k == sym_key(mk_sym(T, :on))) && return true
    (k == sym_key(mk_sym(T, Symbol("false"))) || k == sym_key(mk_sym(T, :off))) &&
        return false
    return nothing
end

# PORT: pl-fli.c PL_get_stdbool
# DIVERGES: returns the Boolean, or `nothing`, where upstream writes it through `b`.
"The Boolean term reference `t` holds — `true`/`on`, `false`/`off`, `1` or `0` — or `nothing` (pl-fli.c)."
function PL_get_stdbool(ld::PL_local_data{T}, t::term_t)::Union{Nothing, Bool} where {T}
    k, x, p = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t) (L1e e2: the words)
    k == DU_WORD && isAtomW(x) && return atom_to_bool(ld, _atom_value(ld, x))   # isAtom(w)
    if k == DU_VALUE                                        # w == consInt(0) / consInt(1)
        isTaggedIntW(x) && valInt(x) == 0 && return false
        isTaggedIntW(x) && valInt(x) == 1 && return true
        return nothing
    end
    k == DU_TERM || return nothing
    ld.cold_pairs += 1                                      # the boundary: on the term
    w = deRef(ld, _loc_term(ld, k, x, p))
    kind(w) === SYM && return atom_to_bool(ld, w)           # isAtom(w)
    if isInteger(w)
        isTaggedInt(w) && int64_value(w) == 0 && return false   # w == consInt(0)
        isTaggedInt(w) && int64_value(w) == 1 && return true
        return nothing
    end
    return nothing
end

# PORT: pl-fli.c PL_get_functor
# DIVERGES: returns `(name, arity)`, or `nothing`, where upstream writes a `functor_t` (as
# `PL_get_name_arity`: an atom goal makes no functor-table entry). On the WORDS (`valHandle(t)`,
# `_deref_loc`): a compound word's functor from the functor table; an atom word (every kernel atom is
# a callable atom or a reserved symbol) as `name/0`. A compound whose head is no symbol (the kernel's
# `$expr/n`) has NO functor here — it names no predicate (query_answers, get_head_functor, callProlog
# refuse it). The boundary is read as its term, counted in `cold_pairs` (f3b-5a).
"The functor of the term `t` references — `(name, arity)` of a compound or an atom — or `nothing` (pl-fli.c)."
function PL_get_functor(
    ld::PL_local_data{T}, t::term_t
)::Union{Nothing, Tuple{T, Int}} where {T}
    k, w, p = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    if k == DU_WORD
        if _is_gcompound(w)                                 # isTerm(w): *f = functorTerm(w)
            f = ld.gstack[valPtr(w)]
            name = nameFunctor(ld.functors, f)
            name == ld.atom_dexpr && return nothing
            return (_atom_value(ld, name), arityFunctor(ld.functors, f))
        end
        return (_atom_value(ld, w), 0)                      # isCallableAtom(w) || isReservedSymbol(w)
    elseif k == DU_TERM                                     # the boundary: on the term
        ld.cold_pairs += 1
        v = deRef(ld, _loc_term(ld, k, w, p))
        if isTerm(v)
            h = child(v, 1)
            return kind(h) === SYM ? (h, nchildren(v) - 1) : nothing
        end
        kind(v) === SYM && return (v, 0)
    end
    return nothing
end

# PORT: pl-fli.c PL_get_intptr
# DIVERGES: the branch of a 64-bit platform whose `long` is a pointer's size (`SIZEOF_LONG ==
# SIZEOF_VOIDP`: Linux, macOS): `PL_get_long`, as `PL_get_intptr_ex`.
"The `intptr_t` term reference `t` holds, or `nothing` (pl-fli.c)."
PL_get_intptr(ld::PL_local_data{T}, t::term_t) where {T} = PL_get_long(ld, t)

# PORT: pl-fli.c PL_get_bool
# DIVERGES: as `PL_get_stdbool` (upstream writes an `int`).
"The Boolean term reference `t` holds, or `nothing` (pl-fli.c)."
PL_get_bool(ld::PL_local_data{T}, t::term_t) where {T} = PL_get_stdbool(ld, t)

# PORT: pl-fli.c PL_get_name_arity_sz as PL_get_name_arity
# DIVERGES: returns `(name, arity)`, or `nothing`, where upstream writes them through pointers; a
# compound whose head is no symbol (the kernel's `$expr/n`) is named `$expr`, its arity the number
# of its children, as the writer writes it. On the WORDS (`valHandle(t)`, `_deref_loc`; L1d step 7b —
# the FLI readers the writer calls, L1e done early): a compound word's functor from the functor table
# (`valueFunctor(functorTerm(w))`), the reserved `$expr` named as above; an atom word's symbol; the
# boundary read as its term, counted in `cold_pairs`.
"The name and arity of the compound or the text atom term reference `t` holds, or `nothing` (pl-fli.c)."
function PL_get_name_arity(
    ld::PL_local_data{T}, t::term_t
)::Union{Nothing, Tuple{T, Int}} where {T}
    k, w, p = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    if k == DU_WORD
        if _is_gcompound(w)                                 # isTerm(w)
            f = ld.gstack[valPtr(w)]                        # functorTerm(w)
            name = nameFunctor(ld.functors, f)
            arity = arityFunctor(ld.functors, f)
            name == ld.atom_dexpr && return (mk_sym(T, Symbol("\$expr")), arity)
            return (_atom_value(ld, name), arity)
        end
        a = _atom_value(ld, w)
        isTextAtom(a) && return (a, 0)                      # isTextAtom(w)
    elseif k == DU_TERM                                     # the boundary: on the term
        ld.cold_pairs += 1
        v = deRef(ld, _loc_term(ld, k, w, p))
        if isTerm(v)
            h = child(v, 1)
            kind(h) === SYM && return (h, nchildren(v) - 1)
            return (mk_sym(T, Symbol("\$expr")), nchildren(v))
        end
        isTextAtom(v) && return (v, 0)
    end
    return nothing
end

# PORT: pl-fli.c _PL_get_arg_sz as _PL_get_arg
# DIVERGES: a compound whose head is no symbol (`$expr/n`) has every child as an argument (see
# `PL_get_name_arity`), so its argument `index` is child `index`; else child `index + 1`.
# On the WORDS (`valHandle(t)`, `_deref_loc`; L1d step 7b — the FLI readers the writer calls, L1e
# done early): a compound word's argument cell into `a` as `linkValI` reads it
# (`_slot_from_cell!`: the cell's word, or a reference to it — an unbound cell, or a value-table word,
# which upstream copies as its indirect and a slot does not hold); on the cells a `$expr/n` compound
# has every child as an argument already. The boundary read as its term, counted in `cold_pairs`.
"Put argument `index` (from 1) of the compound term reference `t` holds into `a` (pl-fli.c)."
function _PL_get_arg(ld::PL_local_data{T}, index::Int, t::term_t, a::term_t)::Bool where {T}
    k, w, p = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    if k == DU_WORD && _is_gcompound(w)
        _slot_from_cell!(ld, a + 1, valPtr(w) + index)      # setHandle(a, linkValI(&f->arguments[index-1]))
        return true
    end
    k == DU_TERM && (ld.cold_pairs += 1)                    # the boundary: on the term
    v = deRef(ld, _loc_term(ld, k, w, p))
    off = kind(child(v, 1)) === SYM ? 1 : 0
    setSlotValue!(ld, a + 1, child(v, index + off))                 # linkValI(&f->arguments[index-1])
    return true
end

# PORT: pl-fli.h PL_is_functor
# DIVERGES: the functor is a name and an arity (upstream: a `functor_t`); on the WORDS (`valHandle(t)`, `_deref_loc`; L1d step 7b — the FLI readers the writer calls, L1e
# done early): a
# compound word's functor compared by arity and name (`hasFunctor`) — a `$expr/n` compound has no
# symbol head, so it is no `name/arity` (as `_hasFunctor` on its term); the boundary read as its
# term, counted in `cold_pairs`.
"Whether term reference `t` holds a compound `name/arity` (pl-fli.h)."
function PL_is_functor(ld::PL_local_data{T}, t::term_t, name::T, arity::Int)::Bool where {T}
    k, w, p = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    if k == DU_WORD
        _is_gcompound(w) || return false                    # hasFunctor(w, f)
        f = ld.gstack[valPtr(w)]
        arityFunctor(ld.functors, f) == arity || return false
        n = nameFunctor(ld.functors, f)
        n == ld.atom_dexpr && return false
        return sym_key(_atom_value(ld, n)) == sym_key(name)
    elseif k == DU_TERM                                     # the boundary: on the term
        ld.cold_pairs += 1
        return _hasFunctor(deRef(ld, _loc_term(ld, k, w, p)), name, arity)
    end
    return false
end

# PORT: pl-fli.c PL_is_pair
# DIVERGES: on the WORDS (`valHandle(t)`, `_deref_loc`; L1d step 7b — the FLI readers the writer calls, L1e
# done early): a compound word whose functor is `'[|]'/2` (`FUNCTOR_dot2`); the
# boundary read as its term, counted in `cold_pairs`.
"Whether term reference `t` holds a list cell (pl-fli.c)."
function PL_is_pair(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    k, w, p = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    if k == DU_WORD
        return _is_gcompound(w) && ld.gstack[valPtr(w)] == ld.functor_dot2   # isList(w)
    elseif k == DU_TERM                                     # the boundary: on the term
        ld.cold_pairs += 1
        return is_pair(deRef(ld, _loc_term(ld, k, w, p)))
    end
    return false
end

# PORT: pl-fli.c PL_get_list
# DIVERGES: on the WORDS (`valHandle(t)`, `_deref_loc`; L1d step 7b — the FLI readers the writer calls, L1e
# done early): a list cell's head and tail cells into `h` and `t` as `linkValI` reads
# them (`_slot_from_cell!`) — the cell's position read first, so `PL_get_list(l, h, l)` holds; the
# boundary read as its term, counted in `cold_pairs`.
"Put the head and the tail of the list cell term reference `l` holds into `h` and `t` (pl-fli.c); false if it holds none."
function PL_get_list(ld::PL_local_data{T}, l::term_t, h::term_t, t::term_t)::Bool where {T}
    k, w, p = _deref_loc(ld, -(l + 1))                      # word w = valHandle(l)
    if k == DU_WORD
        if _is_gcompound(w) && ld.gstack[valPtr(w)] == ld.functor_dot2   # isList(w)
            a = valPtr(w) + 1                               # Word a = argTermP(w, 0)
            _slot_from_cell!(ld, h + 1, a)                  # setHandle(h, linkValI(a++))
            _slot_from_cell!(ld, t + 1, a + 1)              # setHandle(t, linkValI(a))
            return true
        end
    elseif k == DU_TERM                                     # the boundary: on the term
        ld.cold_pairs += 1
        v = deRef(ld, _loc_term(ld, k, w, p))
        if is_pair(v)                                       # isList(w)
            setSlotValue!(ld, h + 1, child(v, 2))                   # linkValI(a++)
            setSlotValue!(ld, t + 1, child(v, 3))
            return true
        end
    end
    return false
end

# PORT: pl-fli.c PL_get_nil
# DIVERGES: on the WORDS (`valHandle(t)`, `_deref_loc`; L1d step 7b — the FLI readers the writer calls, L1e
# done early): the `[]` word (`ATOM_nil`); the boundary read as its term, counted in
# `cold_pairs`.
"Whether term reference `l` holds `[]` (pl-fli.c)."
function PL_get_nil(ld::PL_local_data{T}, l::term_t)::Bool where {T}
    k, w, p = _deref_loc(ld, -(l + 1))                      # word w = valHandle(l)
    k == DU_WORD && return w == ld.atom_nil_w               # isNil(w)
    if k == DU_TERM                                         # the boundary: on the term
        ld.cold_pairs += 1
        return is_nil(deRef(ld, _loc_term(ld, k, w, p)))
    end
    return false
end

# PORT: pl-fli.c PL_is_list
# DIVERGES: on the WORDS (L1e e2): a `'[|]'/2` compound word or ATOM_nil (`isList(w) || isNil(w)`); the
# boundary read as its term, counted in `cold_pairs`.
"Whether term reference `t` holds a list cell or `[]` (pl-fli.c)."
function PL_is_list(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    k, w, p = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    k == DU_WORD && return w == ld.atom_nil_w || _is_list_word(ld, k, w)
    k == DU_TERM || return false
    ld.cold_pairs += 1                                      # the boundary: on the term
    w2 = deRef(ld, _loc_term(ld, k, w, p))
    return is_pair(w2) || is_nil(w2)
end

# ORIGINAL (L1e e2): pl-data.h `hasFunctor(w, FUNCTOR_colon2)` on a dereferenced location's word.
"Whether `(k, w)` from `_deref_loc` is a `:/2` compound word."
@inline function _is_colon2_word(ld::PL_local_data{T}, k::UInt8, w::word)::Bool where {T}
    k == DU_WORD && _is_gcompound(w) || return false
    return ld.gstack[valPtr(w)] ==
           lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :(:))), 2)
end

# ORIGINAL (L1e e2): upstream's `setHandle(h, linkValI(p))` for slot `i` from a dereferenced location
# `(k, w, p)`: an unbound cell its reference (`makeRefG(p)`), any other word itself — but a value-table word
# into a slot older than the innermost foreign frame as its value (e1's rule, `_slot_store!`); the boundary
# (`DU_TERM`) as its term, counted in `cold_pairs`.
"Store in slot `i` what the dereferenced location `(k, w, p)` holds (`setHandle(h, linkValI(p))`)."
function _slot_link_loc!(
    ld::PL_local_data{T}, i::Int, (k, w, p)::Tuple{UInt8, word, Int}
)::Nothing where {T}
    if k == DU_CELL
        ld.slots[i] = makeRefG(p)
    elseif k == DU_TERM
        ld.cold_pairs += 1
        _slot_store!(ld, i, deRef(ld, _loc_term(ld, k, w, p)))
    elseif _is_vword(w) && _slot_older_than_fli(ld, i)
        _slot_store!(ld, i, ld.vtable[valPtr(w)])
    else
        ld.slots[i] = w
    end
    return nothing
end

# PORT: pl-fli.c PL_strip_module_flags as PL_strip_module
# DIVERGES: as `PL_strip_module_ex` — the module an index into `gd`'s table, passed in and returned
# (0 for upstream's NULL), an unqualified term getting `user` when none is given; no `flags`
# (`SM_NOCREATE`: its callers are not ported).
"""
    PL_strip_module(gd, ld, raw, m, plain) -> (ok, m)

Put the term in `raw`, stripped of its atom `Module:` qualifiers, into `plain`, and return the
module they name (pl-fli.c): unlike `PL_strip_module_ex`, a qualifier that is no atom stays.
"""
function PL_strip_module(
    gd::PL_global_data{T}, ld::PL_local_data{T}, raw::term_t, m::Int, plain::term_t
)::Tuple{Bool, Int} where {T}
    k, w, q = _deref_loc(ld, -(raw + 1))                    # p = valTermRef(raw); deRef(p)
    if k != DU_TERM
        if _is_colon2_word(ld, k, w)                        # hasFunctor(*p, FUNCTOR_colon2)
            ok, rc, m2 = stripModule_cells(gd, ld, -(raw + 1))
            if rc[1] != DU_TERM
                ok || return (false, m2)
                _slot_link_loc!(ld, plain + 1, rc)          # setHandle(plain, linkValI(p))
                return (true, m2)
            end
        else
            m == 0 && (m = MODULE_user(gd).index)           # (environment_frame ? contextModule(…) : user)
            raw != plain && _slot_link_loc!(ld, plain + 1, (k, w, q))   # needsRef(*p) ? makeRefG(p) : *p
            return (true, m)
        end
    end
    ld.cold_pairs += 1                                      # the boundary: on terms
    p = deRef(ld, slotValue(ld, raw + 1))
    if _hasFunctor(p, mk_sym(T, :(:)), 2)
        ok, p, m = stripModule(gd, ld, p)
        ok || return (false, m)
        setSlotValue!(ld, plain + 1, p)                             # setHandle(plain, linkValI(p))
    else
        if m == 0
            m = MODULE_user(gd).index               # (environment_frame ? contextModule(…) : user)
        end
        setSlotValue!(ld, plain + 1, p)
    end
    return (true, m)
end

# PORT: pl-fli.c charCode
# DIVERGES: the atom's text is its `sym_text` (since R1): ONE CHARACTER — one code point — gives its
# code, where upstream reads a one-byte ISO-Latin-1 atom or a one-`wchar_t` UCS atom (and, on a
# 2-byte `wchar_t`, a surrogate pair): the same characters, read from UTF-8.
"The character code of the one-character text atom `w`, else -1 (pl-fli.c): `[]` is not text."
function charCode(w)::Int
    if kind(w) === SYM                                      # isAtom(w)
        is_reserved_symbol(w) && return -1                  # not PL_BLOB_TEXT
        s = sym_text(w)
        length(s) == 1 && return Int(s[1])
    end
    return -1
end

# PORT: pl-fli.c PL_strip_module_ex
# DIVERGES: the module is an INDEX into `gd`'s table (0 for upstream's NULL), passed in and returned
# with the result; with none given, an unqualified term gets the context module, `user` (see
# `stripModule`). No `globalizeTermRef` (a keyed variable lives in no cell, decision 2).
"""
    PL_strip_module_ex(gd, ld, raw, m, plain) -> (ok, m)

Put the term in `raw`, stripped of its `Module:` qualifiers, into `plain`, and return the module
they name — `m` if there are none and `m` is given, else `user` (pl-fli.c). A qualifier that is not
an atom raises `type_error(module, M)`, or `instantiation_error` when it is a variable.
"""
function PL_strip_module_ex(
    gd::PL_global_data{T}, ld::PL_local_data{T}, raw::term_t, m::Int, plain::term_t
)::Tuple{Bool, Int} where {T}
    k, w, q = _deref_loc(ld, -(raw + 1))                    # p = valTermRef(raw); deRef(p)
    if k != DU_TERM
        if _is_colon2_word(ld, k, w)                        # hasFunctor(*p, FUNCTOR_colon2)
            ok, rc, m2 = stripModule_cells(gd, ld, -(raw + 1))
            if rc[1] != DU_TERM
                ok || return (false, m2)
                if _is_colon2_word(ld, rc[1], rc[2])        # hasFunctor(*p, FUNCTOR_colon2)
                    a1 = _deref_loc(ld, valPtr(rc[2]) + 1)  # Word a1 = argTermP(*p, 0); deRef(a1)
                    _slot_link_loc!(ld, plain + 1, a1)      # setHandle(plain, linkValI(a1))
                    return (PL_type_error(ld, "module", plain), m2)
                end
                _slot_link_loc!(ld, plain + 1, rc)          # setHandle(plain, linkValI(p))
                return (true, m2)
            end
        else
            m == 0 && (m = MODULE_user(gd).index)           # (environment_frame ? contextModule(…) : user)
            _slot_link_loc!(ld, plain + 1, (k, w, q))       # setHandle(plain, linkValG(p))
            return (true, m)
        end
    end
    ld.cold_pairs += 1                                      # the boundary: on terms
    p = deRef(ld, slotValue(ld, raw + 1))
    if _hasFunctor(p, mk_sym(T, :(:)), 2)
        ok, p, m = stripModule(gd, ld, p)
        ok || return (false, m)
        if _hasFunctor(p, mk_sym(T, :(:)), 2)
            setSlotValue!(ld, plain + 1, deRef(ld, child(p, 2)))    # Word a1 = argTermP(*p, 0)
            return (PL_type_error(ld, "module", plain), m)
        end
        setSlotValue!(ld, plain + 1, p)
    else
        if m == 0
            m = MODULE_user(gd).index               # (environment_frame ? contextModule(…) : user)
        end
        setSlotValue!(ld, plain + 1, p)                     # linkValG(p)
    end
    return (true, m)
end

# PORT: pl-fli.c has_emergency_space as has_emergency_space_local
# DIVERGES: the local stack's (upstream: of the stack passed), in positions.
"""
Whether `needed` positions fit above `lTop` — taking what is lacking from the local stack's spare
(pl-fli.c).
"""
function has_emergency_space_local(ld::PL_local_data{T}, needed::Int)::Bool where {T}
    lacking = ld.lTop + needed - ld.lMax
    lacking <= 0 && return true
    if lacking < ld.local_spare
        ld.lMax += lacking
        ld.local_spare -= lacking
        return true
    end
    return false
end

# PORT: pl-fli.c has_emergency_space as has_emergency_space_global
# DIVERGES (L1f f1b): the global stack's (copy_exception's caller): `lacking` is what `n` more cells take past
# the limit (`_stacks_in_use`), taken from the spare (upstream: `s->max` raised by it).
"Whether `n` more global cells fit, using the global stack's spare if needed (pl-fli.c `has_emergency_space`)."
function has_emergency_space_global(ld::PL_local_data, n::Int)::Bool
    lacking = _stacks_in_use(ld, n) - ld.stacks_limit
    lacking <= 0 && return true
    if lacking < ld.global_spare
        ld.global_spare -= lacking                  # s->max += lacking; s->spare -= lacking
        return true
    end
    return false
end

# PORT: pl-fli.c copy_exception as copy_exception!
# DIVERGES (L1e e5): `duplicate_term(ex, bin)` on the CELLS (`do_copy_term_cells`, share off; L1d step 6)
# into a fresh global cell that `bin` references, as upstream's copy at gTop; PL_raise_exception then
# freezes the global stack (`freezeGlobal!`), so no undo frees the ball — released when the outermost
# query ends (`_release_frozen!`, audit D-0029 option (b): no collector until G1). A ball at the BOUNDARY
# (a keyed variable, a slot's side value) is copied on terms as a value, as before e5 (its trail entries
# dropped), counted — TRANSITIONAL until L1f. A copy that does not fit (L1f f1b: `GLOBAL_OVERFLOW`, the
# frame rewound, nothing raised to clear) takes upstream's three fallbacks in turn: an `error(F, _)` ball
# without its context, `error(resource_error(stack), global)` in the global spare, `abort`. The kernel
# prints none of upstream's three warnings (decision 1). A copy fails only before `exception_processing`
# is set — PL_raise_exception sets it first, as upstream, whose fallbacks need memory exhaustion.
"Copy the ball `ex` references into `bin`, its cycles kept (pl-fli.c)."
function copy_exception!(ld::PL_local_data{T}, ex::term_t, bin::term_t)::Bool where {T}
    fid = PL_open_foreign_frame(ld)
    dest = allocGlobalCells!(ld, 1)             # (L1e e5) duplicate_term() onto the cells, `bin` its reference
    rc = do_copy_term_cells(ld, -(ex + 1), dest, cp_options(false))
    if rc == 1
        ld.slots[bin + 1] = makeRefG(dest)
        PL_close_foreign_frame(ld, fid)
        return true
    elseif rc == CP_BOUNDARY
        ld.cold_pairs += 1                      # the boundary (a keyed variable, a side value): on terms,
        tt = length(ld.trail)                   # the copy a value as before e5 (TRANSITIONAL until L1f)
        _slot_store_value!(
            ld, bin + 1, copy_term(ld, slotValue(ld, ex + 1), cp_options(false))
        )
        _trail_truncate!(ld, tt)                # frozen: the copy's own bindings keep no trail entry
        PL_close_foreign_frame(ld, fid)
        return true
    end
    PL_rewind_foreign_frame(ld, fid)
    PL_clear_exception(ld)
    ld.exception_processing = true
    if PL_is_functor(ld, ex, mk_sym(T, :error), 2)
        arg = PL_new_term_ref(ld)
        f = PL_new_term_ref(ld)
        if _PL_get_arg(ld, 1, ex, arg) && copy_term_refs(ld, arg, f, cp_options(false))
            p = allocGlobalCells!(ld, 3)        # PL_cons_functor_v(bin, FUNCTOR_error2, av)
            ld.gstack[p] = lookupFunctorDef(
                ld.functors, _atom_word!(ld, mk_sym(T, :error)), 2
            )
            ld.gstack[p + 1] = ld.slots[f + 1]  # av+0: the formal's copy; av+1 a fresh variable
            ld.slots[bin + 1] = consPtr(p, TAG_COMPOUND | STG_GLOBAL)
            PL_close_foreign_frame(ld, fid)     # (WARNING: Removed error context …: not printed)
            return true
        end
    elseif has_emergency_space_global(ld, 5)
        p = allocGlobalCells!(ld, 5)            # (WARNING: cannot raise exception …: not printed)
        ld.gstack[p] = lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :error)), 2)
        ld.gstack[p + 1] = consPtr(p + 3, TAG_COMPOUND | STG_GLOBAL)
        ld.gstack[p + 2] = _atom_word!(ld, mk_sym(T, :global))
        ld.gstack[p + 3] = lookupFunctorDef(
            ld.functors, _atom_word!(ld, mk_sym(T, :resource_error)), 1
        )
        ld.gstack[p + 4] = _atom_word!(ld, mk_sym(T, :stack))
        ld.slots[bin + 1] = consPtr(p, TAG_COMPOUND | STG_GLOBAL)
        PL_close_foreign_frame(ld, fid)
        return true
    end
    PL_close_foreign_frame(ld, fid)
    ld.slots[bin + 1] = _atom_word!(ld, mk_sym(T, :abort))   # PL_put_atom(bin, ATOM_abort)
    return true
end

# PORT: pl-fli.c PL_raise_exception
# DIVERGES: the ball is copied by `copy_exception!` (see there: `duplicate_term`, its cycles kept as
# untrailed bindings); `freezeGlobal` is that copy's.
"Make the term `exception` references the pending exception, unless a more urgent one is pending; false (pl-fli.c)."
function PL_raise_exception(ld::PL_local_data{T}, exception::Int)::Bool where {T}
    @assert exception < ld.lTop                             # valTermRef(exception) < lTop
    PL_is_variable(ld, exception) &&                        # if ( PL_is_variable(exception) )
        error("Cannot throw variable exception")            # fatalError()

    ld.exception_processing = true                          # LD->exception.processing = true
    if exception != ld.exception_bin                        # re-throwing
        co = classify_exception(ld, ld.exception_bin)
        cn = classify_exception(ld, exception)
        if cn >= co
            if cn == EXCEPT_RESOURCE
                enableSpareStacks!(ld)
            end
            copy_exception!(ld, exception, ld.exception_bin)
            PL_is_atom(ld, ld.exception_bin) || freezeGlobal!(ld)   # if (!PL_is_atom(exception_bin)) freezeGlobal()
        end
    end
    ld.exception_term = ld.exception_bin

    return false
end

# ── the subset built-ins use (V5a2) ──────────────────────────────────────────────────────────────

# PORT: pl-fli.h PL_is_variable
# DIVERGES: on the WORDS (`valHandle(t)`, `_deref_loc`; L1d step 7b — the FLI readers the writer calls, L1e
# done early): an unbound cell; the boundary read as its term, counted in `cold_pairs`.
"Whether term reference `t` holds an unbound variable (pl-fli.h; `canBind`: no attributed variables)."
function PL_is_variable(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    k, w, p = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    k == DU_CELL && return true                             # canBind(w)
    if k == DU_TERM                                         # the boundary: on the term
        ld.cold_pairs += 1
        return kind(deRef(ld, _loc_term(ld, k, w, p))) === VAR
    end
    return false
end

# The type tests on a term reference (V6b): `valHandle(t)` is the slot dereferenced through the
# bindings; each then asks pl-data.h's test (src/pl-incl.jl).

# PORT: pl-fli.c PL_is_integer
# DIVERGES: on the WORDS (`valHandle(t)`, `_deref_loc`; L1d step 7b — the FLI readers the writer calls, L1e
# done early): a tagged integer, or a value-table word whose entry is an integer
# (upstream's indirect); the boundary read as its term, counted in `cold_pairs`.
"Whether term reference `t` holds an integer (pl-fli.c)."
function PL_is_integer(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    k, w, p = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    if k == DU_VALUE                                        # isInteger(w)
        return isTaggedIntW(w) || isInteger(ld.vtable[valPtr(w)])
    elseif k == DU_TERM                                     # the boundary: on the term
        ld.cold_pairs += 1
        return isInteger(deRef(ld, _loc_term(ld, k, w, p)))
    end
    return false
end

# PORT: pl-fli.c PL_is_float
# DIVERGES: on the WORDS (`valHandle(t)`, `_deref_loc`; L1e e2): a value-table word whose entry is a float
# (upstream's indirect, `isFloat(w)`); the boundary read as its term, counted in `cold_pairs`.
"Whether term reference `t` holds a float (pl-fli.c)."
function PL_is_float(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    k, w, p = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    if k == DU_VALUE                                        # isFloat(w)
        return !isTaggedIntW(w) && isFloat(ld.vtable[valPtr(w)])
    elseif k == DU_TERM                                     # the boundary: on the term
        ld.cold_pairs += 1
        return isFloat(deRef(ld, _loc_term(ld, k, w, p)))
    end
    return false
end

# PORT: pl-fli.c PL_is_rational
# DIVERGES: on the WORDS (L1e e2): a tagged integer, or a value-table word whose entry is an integer or a
# rational (`isRational(w)`); the boundary read as its term, counted in `cold_pairs`.
"Whether term reference `t` holds a rational number, an integer included (pl-fli.c)."
function PL_is_rational(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    k, w, p = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    if k == DU_VALUE                                        # isRational(w)
        return isTaggedIntW(w) || isRational(ld.vtable[valPtr(w)])
    elseif k == DU_TERM                                     # the boundary: on the term
        ld.cold_pairs += 1
        return isRational(deRef(ld, _loc_term(ld, k, w, p)))
    end
    return false
end

# PORT: pl-fli.c PL_is_compound
# DIVERGES: on the WORDS (L1e e2): a compound word (`isTerm(w)`); the boundary read as its term, counted.
"Whether term reference `t` holds a compound term (pl-fli.c)."
function PL_is_compound(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    k, w, p = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    k == DU_WORD && return _is_gcompound(w)                 # isTerm(w)
    if k == DU_TERM                                         # the boundary: on the term
        ld.cold_pairs += 1
        return isTerm(deRef(ld, _loc_term(ld, k, w, p)))
    end
    return false
end

# PORT: pl-fli.c isCallable
# DIVERGES: no closure blobs. A compound with a non-symbol head (`$expr/n`, the kernel's) is not
# callable: its name is no text atom, as `lookupBodyProcedure` refuses it as a goal.
"Whether `t` is callable (pl-fli.c `isCallable`): a text atom, or a compound named by one or by `[]`."
function isCallable(t)::Bool
    if isTerm(t)
        h = child(t, 1)
        return kind(h) === SYM && (!is_reserved_symbol(h) || is_nil(h))  # PL_BLOB_TEXT || ATOM_nil
    end
    return isTextAtom(t)
end

# PORT: pl-fli.c PL_is_callable
# DIVERGES: on the WORDS (L1e e2): a text atom's word, or a compound word whose functor is named by a text
# atom or `[]` (`isCallable`: no closure blobs; a `$expr/n` functor is not callable, as on terms); the
# boundary read as its term, counted in `cold_pairs`.
"Whether term reference `t` holds a callable term (pl-fli.c)."
function PL_is_callable(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    k, w, p = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    if k == DU_WORD
        isAtomW(w) && return isTextAtom(_atom_value(ld, w))
        name = nameFunctor(ld.functors, ld.gstack[valPtr(w)])   # a compound: its functor's name
        name == ld.atom_dexpr && return false
        h = _atom_value(ld, name)
        return !is_reserved_symbol(h) || is_nil(h)          # PL_BLOB_TEXT || ATOM_nil
    elseif k == DU_TERM                                     # the boundary: on the term
        ld.cold_pairs += 1
        return isCallable(deRef(ld, _loc_term(ld, k, w, p)))
    end
    return false
end

# PORT: pl-fli.c PL_is_string
# DIVERGES: on the WORDS (`valHandle(t)`, `_deref_loc`; L1d step 7b — the FLI readers the writer calls, L1e
# done early): a value-table word whose entry is a string (upstream's indirect); the
# boundary read as its term, counted in `cold_pairs`.
"Whether term reference `t` holds a string (pl-fli.c)."
function PL_is_string(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    k, w, p = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    if k == DU_VALUE                                        # isString(w)
        return !isTaggedIntW(w) && isString(ld.vtable[valPtr(w)])
    elseif k == DU_TERM                                     # the boundary: on the term
        ld.cold_pairs += 1
        return isString(deRef(ld, _loc_term(ld, k, w, p)))
    end
    return false
end

# PORT: pl-fli.h PL_is_atom
# DIVERGES: on the WORDS (`valHandle(t)`, `_deref_loc`; L1d step 7b — the FLI readers the writer calls, L1e
# done early): an atom word whose symbol is text (`isTextAtom`); the boundary read as
# its term, counted in `cold_pairs`.
"Whether term reference `t` holds a text atom — not `[]` (pl-fli.h)."
function PL_is_atom(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    k, w, p = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    k == DU_WORD && return isAtomW(w) && isTextAtom(_atom_value(ld, w))   # isTextAtom(w)
    if k == DU_TERM                                         # the boundary: on the term
        ld.cold_pairs += 1
        return isTextAtom(deRef(ld, _loc_term(ld, k, w, p)))
    end
    return false
end

# PORT: pl-fli.h PL_is_atomic
# DIVERGES: on the WORDS (L1e e2): an atom word or a value word (`isAtomic(w)`: neither a variable nor a
# compound); the boundary read as its term, counted in `cold_pairs`.
"Whether term reference `t` holds an atomic term (pl-fli.h)."
function PL_is_atomic(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    k, w, p = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    k == DU_VALUE && return true
    k == DU_WORD && return isAtomW(w)
    if k == DU_TERM                                         # the boundary: on the term
        ld.cold_pairs += 1
        return isAtomic(deRef(ld, _loc_term(ld, k, w, p)))
    end
    return false
end

# PORT: pl-fli.h PL_is_number
# DIVERGES: on the WORDS (`valHandle(t)`, `_deref_loc`; L1d step 7b — the FLI readers the writer calls, L1e
# done early): a tagged integer, or a value-table word whose entry is a number
# (upstream's indirect); the boundary read as its term, counted in `cold_pairs`.
"Whether term reference `t` holds a number (pl-fli.h)."
function PL_is_number(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    k, w, p = _deref_loc(ld, -(t + 1))                      # word w = valHandle(t)
    if k == DU_VALUE                                        # isNumber(w)
        return isTaggedIntW(w) || isNumber(ld.vtable[valPtr(w)])
    elseif k == DU_TERM                                     # the boundary: on the term
        ld.cold_pairs += 1
        return isNumber(deRef(ld, _loc_term(ld, k, w, p)))
    end
    return false
end

# PORT: pl-fli.c PL_unify
# DIVERGES: no `ALLOW_GC|ALLOW_SHIFT`: the kernel's `unify_ptrs` takes no flags, as the binding store
# and the trail cannot overflow during a unification (its DIVERGES). On the CELLS since L1c
# sub-commit 4: the two slots are locations (`unify_ptrs_cells`), as upstream's `valTermRef`s.
"Unify the terms `t1` and `t2` reference (pl-fli.c `PL_unify`); does not undo on failure."
PL_unify(ld::PL_local_data{T}, t1::term_t, t2::term_t) where {T} =
    unify_ptrs_cells(ld, -(t1 + 1), -(t2 + 1))

# PORT: pl-fli.c PL_unify_atomic
# DIVERGES: `w` is an atomic TERM (no words); "the same word" and `equalIndirect` are the standard
# order's identity of two atomic terms (`compare_primitives` in equality mode) — `1` is not `1.0`.
"Unify the term `t` references with the atomic term `w` (pl-fli.c `PL_unify_atomic`)."
function PL_unify_atomic(ld::PL_local_data{T}, t::term_t, w::T)::Bool where {T}
    k, c, q = _deref_loc(ld, -(t + 1))                      # deRef2(valHandleP(t), p) (L1e e3: the cells)
    if k == DU_CELL                                         # canBind(*p)
        _bind_const!(ld, q, _word_of!(ld, w))               # bindConst(p, w): the word made only here
        return true
    elseif k == DU_WORD                                     # *p == w: an atom's word, never a compound's
        return isAtomW(c) && kind(w) === SYM && c == _atom_word!(ld, w)
    elseif k == DU_VALUE                                    # *p == w || equalIndirect(w, *p)
        return compare_primitives(_value_term(ld, c), w, CMP_MODE_EQUAL) == CMP_EQUAL
    end
    ld.cold_pairs += 1                                      # the boundary: on terms
    p = deRef(ld, slotValue(ld, t + 1))
    if kind(p) === VAR                                  # canBind(*p)
        Trail!(ld, var_key(p), w)                       # bindConst(p, w)
        return true
    end
    return compare_primitives(p, w, CMP_MODE_EQUAL) == CMP_EQUAL
end

# PORT: pl-fli.c PL_unify_atom
"Unify the term `t` references with the atom `a` (pl-fli.c `PL_unify_atom`)."
PL_unify_atom(ld::PL_local_data{T}, t::term_t, a::T) where {T} = PL_unify_atomic(ld, t, a)

# PORT: pl-fli.c PL_unify_integer
# (upstream: `unify_int64_ex(t, i, false)` — on the cells since L1d step 7a; L1e e3 drops the term detour)
"Unify the term `t` references with the integer `i` (pl-fli.c `PL_unify_integer`)."
PL_unify_integer(ld::PL_local_data{T}, t::term_t, i::Int) where {T} =
    unify_int64_ex(ld, t, i, false)

# PORT: pl-fli.c unify_int64_ex
# DIVERGES: on the WORDS (`valHandleP(t)`, `_deref_loc`, L1d step 7a): an integer past the tagged range
# (or in a term type holding no `Int64`) is a value-table word (`put_int64`: upstream's indirect); the
# boundary (a slot's side value, a keyed variable) unified on its term (`PL_unify_atomic`), counted in
# `cold_pairs`.
"Unify the term `t` references with the integer `i`; with `ex`, a non-integer is a type error (pl-fli.c)."
function unify_int64_ex(ld::PL_local_data{T}, t::term_t, i::Int, ex::Bool)::Bool where {T}
    k, w, p = _deref_loc(ld, -(t + 1))
    if k == DU_CELL                                         # canBind(*p)
        if PLMINTAGGEDINT <= i <= PLMAXTAGGEDINT && _holds_payload(T, Int64)
            _bind_const!(ld, p, consInt(i))                 # valInt(w) == i: bindConst(p, w)
        else
            _bind_const!(ld, p, _gnd_word!(ld, mk_gnd(T, i)))   # put_int64(&w, i); bindConst
        end
        return true
    elseif k == DU_TERM                                     # the boundary: on the term
        ld.cold_pairs += 1
        return PL_unify_atomic(ld, t, mk_gnd(T, i))
    elseif k == DU_VALUE
        isTaggedIntW(w) && return valInt(w) == i            # w == *p && valInt(w) == i
        v = ld.vtable[valPtr(w)]
        (isInteger(v) && integer_is_int64(v)) && return int64_value(v) == i   # get_int64
        isInteger(v) && return false
    end
    ex && return PL_error(ld, ERR_TYPE, mk_sym(T, :integer), t)   # !isInteger(*p)
    return false
end

# PORT: pl-fli.c PL_unify_int64
"Unify the term `t` references with the integer `i` (pl-fli.c `PL_unify_int64`)."
PL_unify_int64(ld::PL_local_data{T}, t::term_t, i::Int) where {T} =
    unify_int64_ex(ld, t, i, false)

# PORT: pl-fli.h PL_put_intptr
# DIVERGES: `PL_put_int64`'s work, inline: the reference holds the integer — its word since L1e e1 (a tagged
# integer, or a value-table word under `_slot_store!`'s older-slot rule).
"Make term reference `t` hold the integer `i` (pl-fli.h `PL_put_intptr`)."
function PL_put_intptr(ld::PL_local_data{T}, t::term_t, i::Int)::Bool where {T}
    setSlotValue!(ld, t + 1, mk_gnd(T, i))
    return true
end

# PORT: pl-fli.c PL_compare
"The standard order of the terms `t1` and `t2` reference: -1, 0 or 1 (pl-fli.c `PL_compare`)."
PL_compare(ld::PL_local_data{T}, t1::term_t, t2::term_t) where {T} =
    compareStandard_cells(ld, -(t1 + 1), -(t2 + 1), false)    # on the cells (L1d step 1)

# PORT: pl-fli.c PL_clear_exception
"Drop the pending exception, if any (pl-fli.c `PL_clear_exception`)."
function PL_clear_exception(ld::PL_local_data{T})::Nothing where {T}
    if ld.exception_term != 0
        resumeAfterException(ld, true, ld.outofstack)
        ld.outofstack = false
    end
    return nothing
end

# PORT: pl-fli.c PL_clear_foreign_exception
# DIVERGES: nothing is printed — the kernel has no `Serror` (decision 1: no messages); upstream
# prints "Foreign predicate … did not clear exception" and the ball.
"A foreign predicate succeeded with an exception pending: drop it (pl-fli.c)."
function PL_clear_foreign_exception(ld::PL_local_data{T}, fr::Int)::Nothing where {T}
    PL_clear_exception(ld)
    return nothing
end

# PORT: pl-fli.c ucs_atom
# DIVERGES: flags and name only (`PL_blob_t`, src/SWI-Prolog.jl); NOT PORTED: its hooks
# (`compareUCSAtom`, `blob_write_usc_atom`, the qlf `saveUCSAtom`/`loadUCSAtom`).
"The blob type of a wide-character text atom (pl-fli.c): unique, text, `pl_wchar_t` code points."
const ucs_atom = PL_blob_t(PL_BLOB_UNIQUE | PL_BLOB_TEXT | PL_BLOB_WCHAR, "ucs_text")

# PORT: pl-fli.c lookupUCSAtom
# DIVERGES: the table is an argument (`GD->atoms`). The key is upstream's: the code points as
# `pl_wchar_t` — 4 bytes each on Linux, in the machine's byte order — and the length in BYTES
# (`len * sizeof(pl_wchar_t)`).
"The wide text atom of the first `len` code points of `s` (pl-fli.c), created if new."
function lookupUCSAtom(
    atoms::atoms_t, s::AbstractVector{UInt32}, len::Int=length(s)
)::UInt64
    bytes = Vector{UInt8}(reinterpret(UInt8, Vector{UInt32}(view(s, 1:len))))
    return first(lookupBlob(atoms, bytes, len * sizeof(UInt32), ucs_atom))
end
