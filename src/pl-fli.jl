# UPSTREAM: swipl-devel src/pl-fli.c @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  1996-2026, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# THE TERM REFERENCES of SWI-Prolog's foreign language interface (pl-fli.c): a `term_t` is a
# position on the local stack (src/pl-incl.jl § the local stack), allocated at `lTop` inside the
# innermost foreign frame, which counts them. The `PL_get_*`/`PL_put_*`/`PL_unify_*` family the
# built-ins use arrives with them (V5).

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

# PORT: pl-fli.c PL_raise_exception
# DIVERGES: the ball is RESOLVED through the bindings into `exception_bin` (decision 1), so undoing
# bindings cannot change it, where upstream copies it and freezes the global stack under it. There is
# one class of exception (`classify_exception`: resource errors and unwinding are not raised yet), so
# a re-raise replaces the pending ball, as an equal class does upstream.
"Make the term `exception` references the pending exception; returns false (pl-fli.c)."
function PL_raise_exception(ld::PL_local_data{T}, exception::Int)::Bool where {T}
    @assert exception < ld.lTop                             # valTermRef(exception) < lTop
    kind(deRef(ld, ld.slots[exception + 1])) === VAR &&
        error("Cannot throw variable exception")            # fatalError()

    if exception != ld.exception_bin                        # re-throwing
        ld.slots[ld.exception_bin + 1] = resolve_term(ld, ld.slots[exception + 1])
    end
    ld.exception_term = ld.exception_bin

    return false
end
