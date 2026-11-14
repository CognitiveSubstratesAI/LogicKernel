# UPSTREAM: swipl-devel src/pl-flag.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# FLAGS (pl-flag.c), since FL1b: the global flags of `flag/3`'s family: `get_flag/2`, `set_flag/2` and
# `current_flag/1`. A flag is found by its KEY WORD (an atom, a small integer or a compound's functor,
# `getKeyEx`, src/pl-rec.jl) in `gd.flags_table` and holds an atom, an integer or a float
# (`flag`, src/pl-incl.jl). A flag that is read before it was set is made with the integer 0.
# `flag/3` itself is Prolog (boot/init.pl, over these two); `current_flag/1` is an FRG predicate of
# pl-ext.c (the `foreigns` table, src/pl-ext.jl).
#
# DIVERGES (file-wide): no `PL_LOCK(L_FLAG)` (one thread: the lock has nothing to guard); no
# `PL_register_atom`/`PL_unregister_atom` (no atom GC, so `freeFlagValue` has nothing to release and
# neither it nor `freeFlagSymbol`, `cleanupFlags` is written); the table is a `Dict` and the flags are also
# kept in creation order (`gd.flags_order`), which `current_flag/1` enumerates (upstream: the hash
# order, unspecified).

# `initFlags` (pl-flag.c) is a step of the database constructor here, not a function: the two containers of the
# flags are made with the database (src/pl-setup.jl, `flags_table` and `flags_order`).

# PORT: pl-flag.c lookupFlag as lookupFlagKey
# DIVERGES: named `lookupFlagKey` (`lookupFlag` is the prolog flag's, src/os/pl-prologflag.jl); the
# database is the argument; the new flag is also appended to `gd.flags_order`; no atom to register,
# and no race with another thread (`addHTableWP` answering another flag).
"The flag with the key word `key` (pl-flag.c): made with the integer 0 when there is none."
function lookupFlagKey(gd::PL_global_data{T}, key::word)::Flag{T} where {T}
    f = get(gd.flags_table, key, nothing)
    f === nothing || return f
    f = flag{T}(key, FLG_INTEGER, nothing, 0, 0.0)              # f->type = FLG_INTEGER; f->value.i = 0
    gd.flags_table[key] = f                                     # addHTableWP(GD->flags.table, key, f)
    push!(gd.flags_order, f)
    return f
end

# PORT: pl-flag.c get_flag as pl_get_flag2_va
# (PRED_IMPL("get_flag", 2, get_flag, 0))
"`get_flag(+Key, -Value)` (pl-flag.c): `Value` is the atom, integer or float of the flag `Key` (0 when it was never set)."
function pl_get_flag2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    name = PL__t0
    value = PL__t0 + 1
    key = getKeyEx(ld, name)
    key === nothing && return FFALSE
    f = lookupFlagKey(_query_gd(ld), key)
    rc = if f.type == FLG_ATOM
        PL_unify_atom(ld, value, f.a::T)
    elseif f.type == FLG_INTEGER
        PL_unify_int64(ld, value, Int(f.i))
    else                                                        # FLG_FLOAT
        PL_unify_float(ld, value, f.f)
    end
    return rc ? FTRUE : FFALSE
end

# PORT: pl-flag.c set_flag as pl_set_flag2_va
# (PRED_IMPL("set_flag", 2, set_flag, 0))
# DIVERGES: the `type_error` label is the fall-through to the last statement; `V_MPZ` and `V_MPQ` are
# always compiled (O_GMP); the kernel's `V_INTEGER` holds every `Int64` (src/pl-gmp.jl), upstream's only
# the tagged range (+-2^56), where the rest of the 64-bit integers is `V_MPZ`: an integer outside
# `PLMINTAGGEDINT..PLMAXTAGGEDINT` takes the `V_MPZ` branch (`representation_error(int64_t)`, the pin's answer).
"`set_flag(+Key, +Value)` (pl-flag.c): `Value` an atom, a 64-bit integer or a float; else a `type_error(flag_value, Value)`."
function pl_set_flag2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    name = PL__t0
    value = PL__t0 + 1
    key = getKeyEx(ld, name)
    key === nothing && return FFALSE
    f = lookupFlagKey(_query_gd(ld), key)

    a = PL_get_atom(ld, value)
    if a !== nothing
        f.type = FLG_ATOM                                       # freeFlagValue(f); f->type = FLG_ATOM
        f.a = a
        return FTRUE
    end
    n = number()
    if PL_get_number(ld, value, n)
        if n.type === V_INTEGER && PLMINTAGGEDINT <= n.i <= PLMAXTAGGEDINT
            f.type = FLG_INTEGER
            f.i = n.i
            return FTRUE
        elseif n.type === V_MPZ || n.type === V_INTEGER
            PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :int64_t))
            return FFALSE
        elseif n.type === V_FLOAT
            f.type = FLG_FLOAT
            f.f = n.f
            return FTRUE
        end
    end                                                         # V_MPQ and the rest: type_error
    PL_error(ld, "flag", 3, "", ERR_TYPE, mk_sym(T, :flag_value), value)
    return FFALSE
end

# PORT: pl-flag.c pl_current_flag
# (FRG("current_flag", 1, pl_current_flag, NDET), pl-ext.c:173)
# DIVERGES: the enumeration state is the next index in `gd.flags_order`, handed back as an integer
# (`PL_retry`, upstream: a `TableEnum`, `ForeignRedoPtr`), so a cut has nothing to free; the order is
# the creation order.
"`current_flag(?Key)` (pl-flag.c): `Key` is the key of a flag that was made by `get_flag/2` or `set_flag/2`."
function pl_current_flag(
    ld::PL_local_data{T}, k::term_t, ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    ctl = PL_foreign_control(ctx)
    if ctl == FRG_FIRST_CALL
        if PL_is_variable(ld, k)
            e = 1                                               # e = newTableEnumWP(GD->flags.table)
        else
            key = getKeyEx(ld, k)
            (key !== nothing && haskey(gd.flags_table, key)) && return FTRUE
            return FFALSE
        end
    elseif ctl == FRG_REDO
        e = PL_foreign_context(ctx)                             # e = ForeignContextPtr(h)
    else                                                        # FRG_CUTTED: freeTableEnum(e)
        return FTRUE
    end

    fid = PL_open_foreign_frame(ld)
    if fid != 0
        while e <= length(gd.flags_order)                       # while(advanceTableEnum(e, NULL, &v))
            f = gd.flags_order[e]
            e += 1
            if unifyKey(ld, k, f.key)
                PL_close_foreign_frame(ld, fid)
                return PL_retry(e)                              # ForeignRedoPtr(e)
            end
            PL_rewind_foreign_frame(ld, fid)
        end
        PL_close_foreign_frame(ld, fid)
    end
    return FFALSE                                               # freeTableEnum(e)
end

# PORT: pl-flag.c BeginPredDefs as PL_predicates_from_flag
# DIVERGES: `PL_FA_VARARGS` (the table's convention: the arguments are `PL__t0 + i`).
"pl-flag.c's registration table (`BeginPredDefs(flag)`)."
const PL_predicates_from_flag = (
    PL_extension("get_flag", 2, pl_get_flag2_va, PL_FA_VARARGS),
    PL_extension("set_flag", 2, pl_set_flag2_va, PL_FA_VARARGS)
)
