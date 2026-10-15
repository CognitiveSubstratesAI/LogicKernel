# UPSTREAM: swipl-devel src/pl-fli.c @ 8609e216cab9
# UPSTREAM: swipl-devel src/pl-fli.h @ 8609e216cab9
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

    k = allocGlobalVars!(ld, n)
    for i in 0:(n - 1)
        setSlotValue!(ld, t + 1, mk_var(T, k + UInt64(i)))   # setVar(*t++)
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
    setSlotValue!(ld, t + 1, mk_var(T, allocGlobalVars!(ld, 1)))  # setVar(*t++)
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
    setSlotValue!(ld, t + 1, linkValI(ld, slotValue(ld, from + 1)))   # *t = linkValI(valHandleP(from))
    ld.lTop = t + 1
    fr = ld.fli_context
    ld.fliframes[fr].size += 1

    return r
end

# PORT: pl-fli.c PL_cons_list
# DIVERGES: no global space to ensure, so it cannot fail; the cell is a compound of the
# dereferenced head and tail (`bindConsVal`).
"Make term reference `l` hold the list cell of the terms `head` and `tail` reference (pl-fli.c)."
function PL_cons_list(
    ld::PL_local_data{T}, l::term_t, head::term_t, tail::term_t
)::Bool where {T}
    setSlotValue!(
        ld,
        l + 1,
        mk_expr(
            T,
            T[
                mk_sym(T, LIST_CONS_NAME), linkValI(ld, slotValue(ld, head + 1)),
                linkValI(ld, slotValue(ld, tail + 1))
            ]
        )
    )

    return true
end

# PORT: pl-fli.c PL_unify_list
# DIVERGES: no global space to ensure. An unbound list is bound to a cell of two fresh variables.
"Unify term reference `l` with a list cell, putting its head and tail into `h` and `t` (pl-fli.c)."
function PL_unify_list(
    ld::PL_local_data{T}, l::term_t, h::term_t, t::term_t
)::Bool where {T}
    p = deRef(ld, slotValue(ld, l + 1))

    if canBind(p)
        k = allocGlobalVars!(ld, 2)
        a1, a2 = mk_var(T, k), mk_var(T, k + 1)
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
# DIVERGES: returns `(type, length)` where upstream writes the length through `len`. NOT PORTED:
# `tail` (upstream unifies it with the list's tail): no caller here passes one.
"The type of the list term reference `list` holds — `PL_LIST`, `PL_PARTIAL_LIST`, `PL_CYCLIC_TERM`, `PL_NOT_A_LIST` — and its cells (pl-fli.c)."
function PL_skip_list(ld::PL_local_data{T}, list::term_t)::Tuple{Int, Int} where {T}
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
    p = deRef(ld, slotValue(ld, t + 1))

    if canBind(p)
        if arity != 0
            k = allocGlobalVars!(ld, arity)
            a = Vector{T}(undef, 1 + arity)
            a[1] = name
            for i in 1:arity
                a[i + 1] = mk_var(T, k + UInt64(i - 1))    # setVar(a[i])
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

# PORT: pl-fli.c PL_unify_arg_sz as PL_unify_arg
# DIVERGES: a compound whose head is no symbol has every child as an argument (see `_PL_get_arg`).
"Unify argument `index` (from 1) of the compound term reference `t` holds with the term `a` references (pl-fli.c)."
function PL_unify_arg(
    ld::PL_local_data{T}, index::Int, t::term_t, a::term_t
)::Bool where {T}
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
# DIVERGES: no `globalizeTermRef` (as `PL_copy_term_ref`), so it cannot fail.
"Make term reference `t1` reference the term `t2` references (pl-fli.c)."
function PL_put_term(ld::PL_local_data{T}, t1::Int, t2::Int)::Bool where {T}
    setSlotValue!(ld, t1 + 1, linkValI(ld, slotValue(ld, t2 + 1)))    # setHandle(t1, linkValI(p2))
    return true
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
    return classify_exception_p(ld, slotValue(ld, exception + 1))
end

# PORT: pl-fli.c PL_get_atom
# DIVERGES: returns the atom, or `nothing`, where upstream writes it through `a` and returns a Bool.
"The atom term reference `t` holds — a text atom or a reserved symbol such as `[]` — or `nothing` (pl-fli.c)."
function PL_get_atom(ld::PL_local_data{T}, t::term_t)::Union{Nothing, T} where {T}
    w = deRef(ld, slotValue(ld, t + 1))
    kind(w) === SYM && return w                             # isAtom(w)
    return nothing
end

# PORT: pl-fli.c PL_get_integer
# DIVERGES: returns the value, or `nothing`, where upstream writes it through `i`.
"The C `int` term reference `t` holds — a tagged integer in `int`'s range — or `nothing` (pl-fli.c)."
function PL_get_integer(ld::PL_local_data{T}, t::term_t)::Union{Nothing, Int} where {T}
    w = deRef(ld, slotValue(ld, t + 1))
    if isTaggedInt(w)
        val = int64_value(w)
        (val > typemax(Int32) || val < typemin(Int32)) && return nothing
        return Int(val)
    end
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
    w = deRef(ld, slotValue(ld, t + 1))
    kind(w) === SYM && return atom_to_bool(ld, w)           # isAtom(w)
    if isInteger(w)
        isTaggedInt(w) && int64_value(w) == 0 && return false   # w == consInt(0)
        isTaggedInt(w) && int64_value(w) == 1 && return true
        return nothing
    end
    return nothing
end

# PORT: pl-fli.c PL_get_bool
# DIVERGES: as `PL_get_stdbool` (upstream writes an `int`).
"The Boolean term reference `t` holds, or `nothing` (pl-fli.c)."
PL_get_bool(ld::PL_local_data{T}, t::term_t) where {T} = PL_get_stdbool(ld, t)

# PORT: pl-fli.c PL_get_name_arity_sz as PL_get_name_arity
# DIVERGES: returns `(name, arity)`, or `nothing`, where upstream writes them through pointers; a
# compound whose head is no symbol (the kernel's `$expr/n`) is named `$expr`, its arity the number
# of its children, as the writer writes it.
"The name and arity of the compound or the text atom term reference `t` holds, or `nothing` (pl-fli.c)."
function PL_get_name_arity(
    ld::PL_local_data{T}, t::term_t
)::Union{Nothing, Tuple{T, Int}} where {T}
    w = deRef(ld, slotValue(ld, t + 1))
    if isTerm(w)
        h = child(w, 1)
        kind(h) === SYM && return (h, nchildren(w) - 1)
        return (mk_sym(T, Symbol("\$expr")), nchildren(w))
    end
    isTextAtom(w) && return (w, 0)
    return nothing
end

# PORT: pl-fli.c _PL_get_arg_sz as _PL_get_arg
# DIVERGES: a compound whose head is no symbol (`$expr/n`) has every child as an argument (see
# `PL_get_name_arity`), so its argument `index` is child `index`; else child `index + 1`.
"Put argument `index` (from 1) of the compound term reference `t` holds into `a` (pl-fli.c)."
function _PL_get_arg(ld::PL_local_data{T}, index::Int, t::term_t, a::term_t)::Bool where {T}
    w = deRef(ld, slotValue(ld, t + 1))
    off = kind(child(w, 1)) === SYM ? 1 : 0
    setSlotValue!(ld, a + 1, child(w, index + off))                 # linkValI(&f->arguments[index-1])
    return true
end

# PORT: pl-fli.h PL_is_functor
# DIVERGES: the functor is a name and an arity (upstream: a `functor_t`).
"Whether term reference `t` holds a compound `name/arity` (pl-fli.h)."
PL_is_functor(ld::PL_local_data{T}, t::term_t, name::T, arity::Int) where {T} =
    _hasFunctor(deRef(ld, slotValue(ld, t + 1)), name, arity)

# PORT: pl-fli.c PL_get_list
"Put the head and the tail of the list cell term reference `l` holds into `h` and `t` (pl-fli.c); false if it holds none."
function PL_get_list(ld::PL_local_data{T}, l::term_t, h::term_t, t::term_t)::Bool where {T}
    w = deRef(ld, slotValue(ld, l + 1))
    if is_pair(w)                                           # isList(w)
        setSlotValue!(ld, h + 1, child(w, 2))                       # linkValI(a++)
        setSlotValue!(ld, t + 1, child(w, 3))
        return true
    end
    return false
end

# PORT: pl-fli.c PL_get_nil
"Whether term reference `l` holds `[]` (pl-fli.c)."
PL_get_nil(ld::PL_local_data{T}, l::term_t) where {T} =
    is_nil(deRef(ld, slotValue(ld, l + 1)))

# PORT: pl-fli.c PL_is_list
"Whether term reference `t` holds a list cell or `[]` (pl-fli.c)."
function PL_is_list(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    w = deRef(ld, slotValue(ld, t + 1))
    return is_pair(w) || is_nil(w)
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

# PORT: pl-fli.c has_emergency_space
# DIVERGES: the local stack's, in positions.
"""
Whether `needed` positions fit above `lTop` — taking what is lacking from the local stack's spare
(pl-fli.c).
"""
function has_emergency_space(ld::PL_local_data{T}, needed::Int)::Bool where {T}
    lacking = ld.lTop + needed - ld.lMax
    lacking <= 0 && return true
    if lacking < ld.local_spare
        ld.lMax += lacking
        ld.local_spare -= lacking
        return true
    end
    return false
end

# PORT: pl-fli.c copy_exception as copy_exception!
# DIVERGES: upstream's `duplicate_term(ex, bin, 0, 0)` is `copy_term` without sharing
# (src/pl-copyterm.jl): the bindings resolved, each unbound variable a FRESH one — the same for every
# occurrence —, every compound rebuilt. A CYCLIC ball's copy is a fresh variable bound to the copy of
# the term; that binding's trail entry is DROPPED here, so no undo removes it and the ball survives
# the unwind: upstream's `freezeGlobal`, in the kernel's terms (since V5d; user, 2026-10-07).
# NOT PORTED: the fallbacks for a copy that does not fit the global stack (the context dropped, a
# global-stack `resource_error`, `abort`): the copy is a value on Julia's heap; and reclaiming a
# frozen binding: upstream's garbage collector frees a frozen ball once it is unreachable, and the
# kernel's binding store has no collector until G1.
"Copy the ball `ex` references into `bin`, its cycles kept (pl-fli.c)."
function copy_exception!(ld::PL_local_data{T}, ex::term_t, bin::term_t)::Bool where {T}
    tt = length(ld.trail)
    setSlotValue!(ld, bin + 1, copy_term(ld, slotValue(ld, ex + 1), cp_options(false)))     # duplicate_term()
    _trail_truncate!(ld, tt)                    # frozen: the copy's own bindings keep no trail entry
    return true
end

# PORT: pl-fli.c PL_raise_exception
# DIVERGES: the ball is copied by `copy_exception!` (see there: `duplicate_term`, its cycles kept as
# untrailed bindings); `freezeGlobal` is that copy's.
"Make the term `exception` references the pending exception, unless a more urgent one is pending; false (pl-fli.c)."
function PL_raise_exception(ld::PL_local_data{T}, exception::Int)::Bool where {T}
    @assert exception < ld.lTop                             # valTermRef(exception) < lTop
    kind(deRef(ld, slotValue(ld, exception + 1))) === VAR &&
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
        end
    end
    ld.exception_term = ld.exception_bin

    return false
end

# ── the subset built-ins use (V5a2) ──────────────────────────────────────────────────────────────

# PORT: pl-fli.h PL_is_variable
"Whether term reference `t` holds an unbound variable (pl-fli.h; `canBind`: no attributed variables)."
PL_is_variable(ld::PL_local_data{T}, t::term_t) where {T} =
    kind(deRef(ld, slotValue(ld, t + 1))) === VAR

# The type tests on a term reference (V6b): `valHandle(t)` is the slot dereferenced through the
# bindings; each then asks pl-data.h's test (src/pl-incl.jl).

# PORT: pl-fli.c PL_is_integer
"Whether term reference `t` holds an integer (pl-fli.c)."
PL_is_integer(ld::PL_local_data{T}, t::term_t) where {T} =
    isInteger(deRef(ld, slotValue(ld, t + 1)))

# PORT: pl-fli.c PL_is_float
"Whether term reference `t` holds a float (pl-fli.c)."
PL_is_float(ld::PL_local_data{T}, t::term_t) where {T} =
    isFloat(deRef(ld, slotValue(ld, t + 1)))

# PORT: pl-fli.c PL_is_rational
"Whether term reference `t` holds a rational number, an integer included (pl-fli.c)."
PL_is_rational(ld::PL_local_data{T}, t::term_t) where {T} =
    isRational(deRef(ld, slotValue(ld, t + 1)))

# PORT: pl-fli.c PL_is_compound
"Whether term reference `t` holds a compound term (pl-fli.c)."
PL_is_compound(ld::PL_local_data{T}, t::term_t) where {T} =
    isTerm(deRef(ld, slotValue(ld, t + 1)))

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
"Whether term reference `t` holds a callable term (pl-fli.c)."
PL_is_callable(ld::PL_local_data{T}, t::term_t) where {T} =
    isCallable(deRef(ld, slotValue(ld, t + 1)))

# PORT: pl-fli.c PL_is_string
"Whether term reference `t` holds a string (pl-fli.c)."
PL_is_string(ld::PL_local_data{T}, t::term_t) where {T} =
    isString(deRef(ld, slotValue(ld, t + 1)))

# PORT: pl-fli.h PL_is_atom
"Whether term reference `t` holds a text atom — not `[]` (pl-fli.h)."
PL_is_atom(ld::PL_local_data{T}, t::term_t) where {T} =
    isTextAtom(deRef(ld, slotValue(ld, t + 1)))

# PORT: pl-fli.h PL_is_atomic
"Whether term reference `t` holds an atomic term (pl-fli.h)."
PL_is_atomic(ld::PL_local_data{T}, t::term_t) where {T} =
    isAtomic(deRef(ld, slotValue(ld, t + 1)))

# PORT: pl-fli.h PL_is_number
"Whether term reference `t` holds a number (pl-fli.h)."
PL_is_number(ld::PL_local_data{T}, t::term_t) where {T} =
    isNumber(deRef(ld, slotValue(ld, t + 1)))

# PORT: pl-fli.c PL_unify
# DIVERGES: no `ALLOW_GC|ALLOW_SHIFT`: the kernel's `unify_ptrs` takes no flags, as the binding store
# and the trail cannot overflow during a unification (its DIVERGES).
"Unify the terms `t1` and `t2` reference (pl-fli.c `PL_unify`); does not undo on failure."
PL_unify(ld::PL_local_data{T}, t1::term_t, t2::term_t) where {T} =
    unify_ptrs(ld, slotValue(ld, t1 + 1), slotValue(ld, t2 + 1))

# PORT: pl-fli.c PL_unify_atomic
# DIVERGES: `w` is an atomic TERM (no words); "the same word" and `equalIndirect` are the standard
# order's identity of two atomic terms (`compare_primitives` in equality mode) — `1` is not `1.0`.
"Unify the term `t` references with the atomic term `w` (pl-fli.c `PL_unify_atomic`)."
function PL_unify_atomic(ld::PL_local_data{T}, t::term_t, w::T)::Bool where {T}
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
# DIVERGES: every `Int` is one grounded value — no `consInt` range and no `unify_int64_ex`.
"Unify the term `t` references with the integer `i` (pl-fli.c `PL_unify_integer`)."
PL_unify_integer(ld::PL_local_data{T}, t::term_t, i::Int) where {T} =
    PL_unify_atomic(ld, t, mk_gnd(T, i))

# PORT: pl-fli.h PL_put_intptr
# DIVERGES: `PL_put_int64`'s work, inline: the reference holds the integer.
"Make term reference `t` hold the integer `i` (pl-fli.h `PL_put_intptr`)."
function PL_put_intptr(ld::PL_local_data{T}, t::term_t, i::Int)::Bool where {T}
    setSlotValue!(ld, t + 1, mk_gnd(T, i))
    return true
end

# PORT: pl-fli.c PL_compare
"The standard order of the terms `t1` and `t2` reference: -1, 0 or 1 (pl-fli.c `PL_compare`)."
PL_compare(ld::PL_local_data{T}, t1::term_t, t2::term_t) where {T} =
    compareStandard(ld, slotValue(ld, t1 + 1), slotValue(ld, t2 + 1), false)

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
