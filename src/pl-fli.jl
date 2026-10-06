# UPSTREAM: swipl-devel src/pl-fli.c @ bae881a24a3f
# UPSTREAM: swipl-devel src/pl-fli.h @ bae881a24a3f
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

    k = fresh_var_keys!(n)
    for i in 0:(n - 1)
        ld.slots[t + 1] = mk_var(T, k + UInt64(i))   # setVar(*t++)
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
    ld.slots[t + 1] = mk_var(T, fresh_var_keys!(1))  # setVar(*t++)
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
    ld.slots[t + 1] = linkValI(ld, ld.slots[from + 1])   # *t = linkValI(valHandleP(from))
    ld.lTop = t + 1
    fr = ld.fli_context
    ld.fliframes[fr].size += 1

    return r
end

# PORT: pl-fli.c PL_put_term
# DIVERGES: no `globalizeTermRef` (as `PL_copy_term_ref`), so it cannot fail.
"Make term reference `t1` reference the term `t2` references (pl-fli.c)."
function PL_put_term(ld::PL_local_data{T}, t1::Int, t2::Int)::Bool where {T}
    ld.slots[t1 + 1] = linkValI(ld, ld.slots[t2 + 1])    # setHandle(t1, linkValI(p2))
    return true
end

# (untyped: an implementation's leaves may be of different concrete types under one term type)
"`p` is a compound `name/arity` (`hasFunctor`): a symbol head named `name` and `arity` arguments."
_hasFunctor(p, name, arity::Int) =
    kind(p) === EXPR && nchildren(p) == arity + 1 && kind(child(p, 1)) === SYM &&
    sym_key(child(p, 1)) == sym_key(name)

# PORT: pl-fli.c classify_exception_p
# KNOWN UPSTREAM DEFECT, ported AS IS (docs/upstream_reports.md #5): `error(F, _)` is
# `EXCEPT_RESOURCE` only when `F` is the ATOM `resource_error`, where pl-incl.h documents the class as
# `error(resource_error(_), _)` — so the stack overflow's `error(resource_error(stack), _)` ranks as an
# ordinary error (probed: `'$urgent_exception'/3` keeps a type error over it).
"The class of the ball `p` (pl-fli.c `classify_exception_p`)."
function classify_exception_p(ld::PL_local_data{T}, p::T)::except_class where {T}
    p = deRef(ld, p)
    if kind(p) === VAR
        return EXCEPT_NONE
    elseif kind(p) === SYM
        sym_key(p) == sym_key(mk_sym(T, :time_limit_exceeded)) && return EXCEPT_TIMEOUT
    elseif _hasFunctor(p, mk_sym(T, :error), 2)
        a = deRef(ld, child(p, 2))                          # p = argTermP(*p, 0)
        if kind(a) === SYM && sym_key(a) == sym_key(mk_sym(T, :resource_error))
            return EXCEPT_RESOURCE
        end
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
    return classify_exception_p(ld, ld.slots[exception + 1])
end

# PORT: pl-fli.c PL_raise_exception
# DIVERGES: the ball is RESOLVED through the bindings into `exception_bin` (decision 1), so undoing
# bindings cannot change it, where upstream copies it and freezes the global stack under it.
# NOT PORTED: `enableSpareStacks` for a resource error — there are no spare stacks. V5d raises the
# stack limit's error, as decided since Q-B, and decides whether the local stack gets its spare.
"Make the term `exception` references the pending exception, unless a more urgent one is pending; false (pl-fli.c)."
function PL_raise_exception(ld::PL_local_data{T}, exception::Int)::Bool where {T}
    @assert exception < ld.lTop                             # valTermRef(exception) < lTop
    kind(deRef(ld, ld.slots[exception + 1])) === VAR &&
        error("Cannot throw variable exception")            # fatalError()

    if exception != ld.exception_bin                        # re-throwing
        co = classify_exception(ld, ld.exception_bin)
        cn = classify_exception(ld, exception)
        if cn >= co                                         # (EXCEPT_RESOURCE: enableSpareStacks)
            ld.slots[ld.exception_bin + 1] = resolve_term(ld, ld.slots[exception + 1])
        end
    end
    ld.exception_term = ld.exception_bin

    return false
end

# ── the subset built-ins use (V5a2) ──────────────────────────────────────────────────────────────

# PORT: pl-fli.h PL_is_variable
"Whether term reference `t` holds an unbound variable (pl-fli.h; `canBind`: no attributed variables)."
PL_is_variable(ld::PL_local_data{T}, t::term_t) where {T} =
    kind(deRef(ld, ld.slots[t + 1])) === VAR

# The type tests on a term reference (V6b): `valHandle(t)` is the slot dereferenced through the
# bindings; each then asks pl-data.h's test (src/pl-incl.jl).

# PORT: pl-fli.c PL_is_integer
"Whether term reference `t` holds an integer (pl-fli.c)."
PL_is_integer(ld::PL_local_data{T}, t::term_t) where {T} =
    isInteger(deRef(ld, ld.slots[t + 1]))

# PORT: pl-fli.c PL_is_float
"Whether term reference `t` holds a float (pl-fli.c)."
PL_is_float(ld::PL_local_data{T}, t::term_t) where {T} = isFloat(deRef(ld, ld.slots[t + 1]))

# PORT: pl-fli.c PL_is_rational
"Whether term reference `t` holds a rational number, an integer included (pl-fli.c)."
PL_is_rational(ld::PL_local_data{T}, t::term_t) where {T} =
    isRational(deRef(ld, ld.slots[t + 1]))

# PORT: pl-fli.c PL_is_compound
"Whether term reference `t` holds a compound term (pl-fli.c)."
PL_is_compound(ld::PL_local_data{T}, t::term_t) where {T} =
    isTerm(deRef(ld, ld.slots[t + 1]))

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
    isCallable(deRef(ld, ld.slots[t + 1]))

# PORT: pl-fli.c PL_is_string
"Whether term reference `t` holds a string (pl-fli.c)."
PL_is_string(ld::PL_local_data{T}, t::term_t) where {T} =
    isString(deRef(ld, ld.slots[t + 1]))

# PORT: pl-fli.h PL_is_atom
"Whether term reference `t` holds a text atom — not `[]` (pl-fli.h)."
PL_is_atom(ld::PL_local_data{T}, t::term_t) where {T} =
    isTextAtom(deRef(ld, ld.slots[t + 1]))

# PORT: pl-fli.h PL_is_atomic
"Whether term reference `t` holds an atomic term (pl-fli.h)."
PL_is_atomic(ld::PL_local_data{T}, t::term_t) where {T} =
    isAtomic(deRef(ld, ld.slots[t + 1]))

# PORT: pl-fli.h PL_is_number
"Whether term reference `t` holds a number (pl-fli.h)."
PL_is_number(ld::PL_local_data{T}, t::term_t) where {T} =
    isNumber(deRef(ld, ld.slots[t + 1]))

# PORT: pl-fli.c PL_unify
# DIVERGES: no `ALLOW_GC|ALLOW_SHIFT`: the kernel's `unify_ptrs` takes no flags, as the binding store
# and the trail cannot overflow during a unification (its DIVERGES).
"Unify the terms `t1` and `t2` reference (pl-fli.c `PL_unify`); does not undo on failure."
PL_unify(ld::PL_local_data{T}, t1::term_t, t2::term_t) where {T} =
    unify_ptrs(ld, ld.slots[t1 + 1], ld.slots[t2 + 1])

# PORT: pl-fli.c PL_unify_atomic
# DIVERGES: `w` is an atomic TERM (no words); "the same word" and `equalIndirect` are the standard
# order's identity of two atomic terms (`compare_primitives` in equality mode) — `1` is not `1.0`.
"Unify the term `t` references with the atomic term `w` (pl-fli.c `PL_unify_atomic`)."
function PL_unify_atomic(ld::PL_local_data{T}, t::term_t, w::T)::Bool where {T}
    p = deRef(ld, ld.slots[t + 1])
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
    ld.slots[t + 1] = mk_gnd(T, i)
    return true
end

# PORT: pl-fli.c PL_compare
"The standard order of the terms `t1` and `t2` reference: -1, 0 or 1 (pl-fli.c `PL_compare`)."
PL_compare(ld::PL_local_data{T}, t1::term_t, t2::term_t) where {T} =
    compareStandard(ld, ld.slots[t1 + 1], ld.slots[t2 + 1], false)

# PORT: pl-fli.c PL_clear_exception
# NOT PORTED: `LD->outofstack`, which `resumeAfterException` reads, until V5d raises the stack
# limit's error, as decided since Q-B.
"Drop the pending exception, if any (pl-fli.c `PL_clear_exception`)."
function PL_clear_exception(ld::PL_local_data{T})::Nothing where {T}
    if ld.exception_term != 0
        resumeAfterException(ld, true)
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
