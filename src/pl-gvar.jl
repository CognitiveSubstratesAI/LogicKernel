# UPSTREAM: swipl-devel src/pl-gvar.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  2004-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# PIN1 ledger (V10.1.20): structure only, d755bdc4 — pl-gvar.c: cell-tag access behind pl-data.h macros, no change of value, order, error or side effect.
# GLOBAL VARIABLES (pl-gvar.c): `b_setval/2`, `b_getval/2`, `nb_setval/2`, `nb_linkval/2`,
# `nb_getval/2`, `nb_current/2` and `nb_delete/1`. A global variable is an entry of the thread's table
# (`LD->gvar.nb_vars`, here `ld.gvar_nb_vars`: atom word -> the value's word). A value on the global
# stack keeps the stack FROZEN below it (`freezeGlobal!`, src/pl-inline.jl) and is counted in
# `gvar_grefs`, which `_release_frozen!` honours (design D7). `b_setval` moves the value into a cell of
# its own and trails the assignment to it. A name nobody set calls `user:exception/3`
# (`auto_define_gvar`, design D8).
#
# NOT PORTED: `destroyGlobalVars` (a thread's end), `PL_register_atom`/`PL_unregister_atom` of a name or
# an atom value (the kernel has no atom GC), the table's `free_symbol` hook (`free_nb_linkval_symbol`),
# and `duplicate_term`'s `nshare`/`share` arguments (src/pl-copyterm.jl).

# PORT: pl-gvar.c SETVAL_BACKTRACKABLE
"`setval`'s flag: the assignment is undone on backtracking (`b_setval/2`)."
const SETVAL_BACKTRACKABLE = UInt32(0x1)
# PORT: pl-gvar.c SETVAL_LINK
"`setval`'s flag: the value is shared, not copied (`nb_linkval/2`)."
const SETVAL_LINK = UInt32(0x2)

# PORT: pl-gvar.c gvar_action as gvar_fail
# DIVERGES: typed constants, not an `enum` (the manifest of enum hashes stays as it is).
"`auto_define_gvar`'s answer: the hook says fail (pl-gvar.c `gvar_action`)."
const gvar_fail = Int8(0)
"`auto_define_gvar`'s answer: look the name up again (pl-gvar.c `gvar_action`)."
const gvar_retry = Int8(1)
"`auto_define_gvar`'s answer: the variable does not exist (pl-gvar.c `gvar_action`)."
const gvar_error = Int8(2)

# ORIGINAL: the word of the atom `no_value`, which stands for "no value" in the table.
"The atom word of `no_value` (pl-atom.h `ATOM_no_value`)."
_gvar_no_value(ld::PL_local_data{T}) where {T} = _atom_word!(ld, mk_sym(T, :no_value))

# ORIGINAL: `storage(w) == STG_GLOBAL` for the kernel's words: a float, a string or a big number is a
# value-table word (`STG_RESERVED`), upstream's indirect on the global stack (`STG_GLOBAL`).
"Whether the word `w` lives on the global stack (upstream: `storage(w) == STG_GLOBAL`)."
_gvar_on_global(w::word)::Bool = storage(w) == STG_GLOBAL || _is_vword(w)

# PORT: pl-gvar.c new_gvar as new_gvar!
# DIVERGES: the table is made with the local data; the atom is not registered (no atom GC). `name` and
# `value` are words.
"Add global variable `name` with `value` (pl-gvar.c `new_gvar`); `value`."
function new_gvar!(ld::PL_local_data, name::word, value::word)::word
    ld.gvar_nb_vars[name] = value                   # addNewHTable(LD->gvar.nb_vars, name, old)
    return value
end

# PORT: pl-gvar.c lookup_gvar
# DIVERGES: 0 (no value word is 0) for a name without an entry.
"The word global variable `name` holds, or 0 (pl-gvar.c `lookup_gvar`)."
lookup_gvar(ld::PL_local_data, name::word)::word = get(ld.gvar_nb_vars, name, word(0))

# PORT: pl-gvar.c PL_getval
# DIVERGES: the name is an atom word.
"Make term reference `val` hold the value of global variable `name`; false when there is none (pl-gvar.c)."
function PL_getval(
    ld::PL_local_data, name::word, val::term_t, flags::UInt32=UInt32(0)
)::Bool
    w = lookup_gvar(ld, name)
    if w != 0
        ld.slots[val + 1] = w                       # *valTermRef(val) = w
        return true
    end
    return false
end

# PORT: pl-gvar.c word_is_attvar
"Whether `w`, followed through its references, is an attributed variable (pl-gvar.c)."
function word_is_attvar(ld::PL_local_data, w::word)::Bool
    while isRef(w)
        w = ld.gstack[unRef(w)]                     # w = *unRef(w)
    end
    return isAttVar(w)
end

# PORT: pl-gvar.c setval_duplicate
# DIVERGES: `old` is not shared with the copy (`duplicate_term`'s `nshare`/`share` are not ported: the
# copy is a whole one). The word 0 is upstream's NULL.
"The word of a copy of `new` when it is a compound or an attributed variable, else `new`; 0 when the copy fails (pl-gvar.c)."
function setval_duplicate(ld::PL_local_data, new::word, old::word)::word
    if _is_gcompound(new) || word_is_attvar(ld, new)    # isTerm(new) || word_is_attvar(new)
        from = PL_new_term_ref(ld)
        copy = PL_new_term_ref(ld)
        ld.slots[from + 1] = new                    # *valTermRef(from) = new
        if duplicate_term(ld, from, copy)
            return ld.slots[copy + 1]               # *valTermRef(copy)
        else
            return word(0)
        end
    else
        return new
    end
end

# PORT: pl-gvar.c setval as gvar_setval
# DIVERGES: a term reference is never an unbound cell of the local stack, so `canBind`'s
# `onStackArea(local, p)` branch (a fresh global cell for the local variable) has no case: a variable is
# the reference to its global cell. A side value (D-0024) gets a value-table word first. An atom is not
# registered or unregistered (no atom GC). `ensureGlobalSpace(3, ALLOW_GC)` is `ensureGlobalSpace(3)`.
"Assign `value` to global variable `var`: `flags` `SETVAL_BACKTRACKABLE` trails the assignment, `SETVAL_LINK` shares the value (pl-gvar.c)."
function gvar_setval(
    ld::PL_local_data{T}, var::term_t, value::term_t, flags::UInt32
)::Bool where {T}
    a = PL_get_atom_ex(ld, var)
    a === nothing && return false
    name = _atom_word!(ld, a)

    ensureGlobalSpace(ld, 3, ALLOW_GC, :setval) || return false        # also ensures trail for TrailAssignment()   # G1-GC safe point: setval

    k, w, q = _deref_loc(ld, -(value + 1))          # p = valTermRef(value); deRef(p); w = *p
    if k == DU_CELL || k == DU_ATTVAR               # canBind(w)
        w = makeRefG(q)
    elseif _is_side_word(w)
        w = _value_word!(ld, w)
    end

    old = lookup_gvar(ld, name)
    if old == 0
        old = new_gvar!(ld, name, _gvar_no_value(ld))
    end

    w == old && return true
    # (isAtom(old): PL_unregister_atom(word2atom(old)) — no atom GC)

    if (flags & SETVAL_BACKTRACKABLE) != 0
        if isRef(old)
            p = unRef(old)
        else
            p = allocGlobalCells!(ld, 1)
            ld.gstack[p] = old                      # *p = old
            freezeGlobal!(ld)                       # The value location must be preserved
            if !_gvar_on_global(old)                # storage(old) != STG_GLOBAL
                ld.gvar_grefs += 1
            end
            ld.gvar_nb_vars[name] = makeRefG(p)     # updateHTable(…, makeRefG(p))
        end

        TrailAssignment!(ld, p)
        ld.gstack[p] = w                            # *p = w
    else
        old_on_global = _gvar_on_global(old)

        if (flags & SETVAL_LINK) == 0
            w = setval_duplicate(ld, w, old)
            w == 0 && return false
        end
        if old_on_global
            ld.gvar_grefs -= 1
        end

        ld.gvar_nb_vars[name] = w                   # updateHTable(…, w)

        if _gvar_on_global(w)
            freezeGlobal!(ld)
            ld.gvar_grefs += 1
        end
        # (else if isAtom(w): PL_register_atom — no atom GC)
    end

    return true
end

# PORT: pl-gvar.c auto_define_gvar
# DIVERGES: `user:exception/3` is looked up on each call (no `GD->procedures.exception3`); it exists as a
# dynamic predicate from the start (design D8, `setBuiltinPredicateProperties!`). Upstream assigns
# `PL_get_atom_ex`'s truth value to the enum (`rc = PL_get_atom_ex(..)`): an answer other than `retry` or
# `fail` is `true` = 1 = `gvar_retry`, so the name is looked up and the hook called once more, then the
# existence error; a non-atom answer is 0 = `gvar_fail` with the type error raised. Kept as is.
"Call `user:exception(undefined_global_variable, Name, Action)`; what to do next (pl-gvar.c)."
function auto_define_gvar(ld::PL_local_data{T}, name::word)::Int8 where {T}
    gd = _query_gd(ld)
    pred = lookupProcedure(mk_sym(T, :exception), 3, MODULE_user(gd))
    rc = gvar_error

    fid = PL_open_foreign_frame(ld)
    fid == 0 && return gvar_error
    av = PL_new_term_refs(ld, 3)
    PL_put_atom(ld, av, mk_sym(T, :undefined_global_variable))
    PL_put_atom(ld, av + 1, _atom_value(ld, name))

    if PL_call_predicate(gd, ld, nothing, PL_Q_PASS_EXCEPTION, pred, av)
        action = PL_get_atom_ex(ld, av + 2)         # retry, error, fail
        rc = action === nothing ? gvar_fail : gvar_retry
        if action !== nothing
            text = sym_text(action)
            if text == "retry"
                rc = gvar_retry
            elseif text == "fail"
                rc = gvar_fail
            end
        end
    end

    PL_close_foreign_frame(ld, fid)

    return rc
end

# PORT: pl-gvar.c gvar_value
# DIVERGES: the word, or `nothing` where upstream's `bool` says no (upstream stores it through `Word p`).
"The word global variable `name` holds, or `nothing`; does not call the hook (pl-gvar.c)."
function gvar_value(ld::PL_local_data, name::word)::Union{Nothing, word}
    w = lookup_gvar(ld, name)
    return w != 0 ? w : nothing
end

# PORT: pl-gvar.c is_gval
"Whether global variable value `w`, through one reference, is not `no_value` (pl-gvar.c)."
function is_gval(ld::PL_local_data, w::word)::Bool
    if isRef(w)
        w = ld.gstack[unRef(w)]                     # w = *unRef(w)
    end
    return w != _gvar_no_value(ld)
end

# PORT: pl-gvar.c getval as gvar_getval
# DIVERGES: the value word is put in a term reference (a slot holds any value word), unified with
# `value`; `PL_error` returns false.
"Unify `value` with the value of global variable `var`, asking the hook for a name nobody set (pl-gvar.c)."
function gvar_getval(
    ld::PL_local_data{T}, var::term_t, value::term_t, raise_error::Bool
)::Bool where {T}
    a = PL_get_atom_ex(ld, var)
    a === nothing && return false
    name = _atom_word!(ld, a)

    for i in 0:1
        w = lookup_gvar(ld, name)
        if w != 0
            if is_gval(ld, w)
                tmp = PL_new_term_ref(ld)
                ld.slots[tmp + 1] = w               # *valTermRef(tmp) = w
                return PL_unify(ld, value, tmp)
            else
                break
            end
        end

        action = auto_define_gvar(ld, name)
        if action == gvar_fail
            new_gvar!(ld, name, _gvar_no_value(ld))
            return false
        elseif action == gvar_retry
            continue
        else                                        # gvar_error
            ld.exception_term != 0 && return false  # error from handler
            new_gvar!(ld, name, _gvar_no_value(ld))
            break                                   # goto error
        end
    end

    if raise_error
        return PL_error(ld, ERR_EXISTENCE, mk_sym(T, :variable), var)
    else
        return false
    end
end

# PORT: pl-gvar.c nb_setval as pl_nb_setval2_va
# (PRED_IMPL("nb_setval", 2, nb_setval, 0))
"`nb_setval(+Key, +Value)`: a copy of `Value` is the value of global variable `Key` (pl-gvar.c)."
function pl_nb_setval2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    return gvar_setval(ld, A1, A2, UInt32(0)) ? FTRUE : FFALSE
end

# PORT: pl-gvar.c nb_linkval as pl_nb_linkval2_va
# (PRED_IMPL("nb_linkval", 2, nb_linkval, 0))
"`nb_linkval(+Key, +Value)`: `Value` itself, not a copy, is the value of global variable `Key` (pl-gvar.c)."
function pl_nb_linkval2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    return gvar_setval(ld, A1, A2, SETVAL_LINK) ? FTRUE : FFALSE
end

# PORT: pl-gvar.c nb_getval as pl_nb_getval2_va
# (PRED_IMPL("nb_getval", 2, nb_getval, 0))
"`nb_getval(+Key, -Value)`: the value of global variable `Key`; an existence error without one (pl-gvar.c)."
function pl_nb_getval2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    return gvar_getval(ld, A1, A2, true) ? FTRUE : FFALSE
end

# PORT: pl-gvar.c b_setval as pl_b_setval2_va
# (PRED_IMPL("b_setval", 2, b_setval, 0))
"`b_setval(+Key, +Value)`: assign `Value` to global variable `Key`, undone on backtracking (pl-gvar.c)."
function pl_b_setval2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    return gvar_setval(ld, A1, A2, SETVAL_BACKTRACKABLE) ? FTRUE : FFALSE
end

# PORT: pl-gvar.c b_getval as pl_b_getval2_va
# (PRED_IMPL("b_getval", 2, b_getval, 0))
"`b_getval(+Key, -Value)`: the value of global variable `Key` (pl-gvar.c)."
function pl_b_getval2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    return gvar_getval(ld, A1, A2, true) ? FTRUE : FFALSE
end

# PORT: pl-gvar.c nb_delete as pl_nb_delete1_va
# (PRED_IMPL("nb_delete", 1, nb_delete, 0))
# DIVERGES: upstream's `LD->gvar.nb_vars` is NULL until the first variable is made; the table here is
# made with the local data, and being empty stands for NULL (no entry is ever removed).
"`nb_delete(+Key)`: global variable `Key` has no value; the hook is not asked for it again (pl-gvar.c)."
function pl_nb_delete1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    a = PL_get_atom_ex(ld, A1)
    a === nothing && return FFALSE
    name = _atom_word!(ld, a)

    if !isempty(ld.gvar_nb_vars)                    # if ( LD->gvar.nb_vars )
        no_value = _gvar_no_value(ld)
        w = lookup_gvar(ld, name)
        if w != 0
            if w != no_value
                if _gvar_on_global(w)               # free_nb_linkval_value(w)
                    ld.gvar_grefs -= 1
                end
                ld.gvar_nb_vars[name] = no_value    # updateHTable(…, ATOM_no_value)
            end
        else
            new_gvar!(ld, name, no_value)
        end
    end

    return FTRUE
end

# PORT: pl-gvar.c nb_current as pl_nb_current2_va
# (PRED_IMPL("nb_current", 2, nb_current, PL_FA_NONDETERMINISTIC))
# DIVERGES: the state is a record of the local data's pool (`ld.gvar_enums`), its index the `REDO_PTR`
# context; the names are those of the table at the first call, in its order (upstream's hash order), each
# read again when its turn comes. The foreign frame is closed before a retry (as current_prolog_flag/2).
"`nb_current(?Key, ?Value)`: the global variables that have a value, one per answer (pl-gvar.c)."
function pl_nb_current2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    pool = ld.gvar_enums

    ctl = PL_foreign_control(PL__ctx)
    if ctl == FRG_FIRST_CALL
        if PL_is_atom(ld, A1)
            return gvar_getval(ld, A1, A2, false) ? FTRUE : FFALSE
        end
        if !PL_is_variable(ld, A1)
            return PL_type_error(ld, "atom", A1) ? FTRUE : FFALSE
        end
        isempty(ld.gvar_nb_vars) && return FFALSE   # LD->gvar.nb_vars is NULL
        idx = alloc_foreign_state!(pool)            # e = newTableEnum(LD->gvar.nb_vars)
        e = pool.states[idx]
        resize!(e.keys, 0)
        append!(e.keys, keys(ld.gvar_nb_vars))
        e.next = 1
    elseif ctl == FRG_REDO
        idx = PL_foreign_context_address(PL__ctx)   # e = CTX_PTR
        e = pool.states[idx]
    else                                            # FRG_CUTTED
        free_foreign_state!(pool, PL_foreign_context_address(PL__ctx))
        return FTRUE
    end

    fid = PL_open_foreign_frame(ld)
    if fid == 0
        free_foreign_state!(pool, idx)
        return FFALSE
    end

    while e.next <= length(e.keys)                  # advanceTableEnum(e, &tk, &tv)
        name = e.keys[e.next]
        e.next += 1
        val = lookup_gvar(ld, name)

        (val != 0 && is_gval(ld, val)) || continue
        tmp = PL_new_term_ref(ld)
        ld.slots[tmp + 1] = val                     # unify_ptrs(valTermRef(A2), &val, 0)
        if PL_unify_atom(ld, A1, _atom_value(ld, name)) && PL_unify(ld, A2, tmp)
            PL_close_foreign_frame(ld, fid)
            return PL_retry_address(idx)            # ForeignRedoPtr(e)
        else
            PL_rewind_foreign_frame(ld, fid)
        end
    end
    PL_close_foreign_frame(ld, fid)

    free_foreign_state!(pool, idx)                  # freeTableEnum(e)
    return FFALSE
end

# PORT: pl-gvar.c BeginPredDefs as PL_predicates_from_gvar
"pl-gvar.c's registration table (`BeginPredDefs(gvar)`)."
const PL_predicates_from_gvar = (
    PL_extension("b_setval", 2, pl_b_setval2_va, PL_FA_VARARGS),
    PL_extension("b_getval", 2, pl_b_getval2_va, PL_FA_VARARGS),
    PL_extension("nb_setval", 2, pl_nb_setval2_va, PL_FA_VARARGS),
    PL_extension("nb_linkval", 2, pl_nb_linkval2_va, PL_FA_VARARGS),
    PL_extension("nb_getval", 2, pl_nb_getval2_va, PL_FA_VARARGS),
    PL_extension(
        "nb_current", 2, pl_nb_current2_va, PL_FA_NONDETERMINISTIC | PL_FA_VARARGS
    ),
    PL_extension("nb_delete", 1, pl_nb_delete1_va, PL_FA_VARARGS)
)
