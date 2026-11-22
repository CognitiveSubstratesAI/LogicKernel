# UPSTREAM: swipl-devel src/pl-flag.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# What the kernel takes from SWI-Prolog's flag database (pl-flag.c, owner FL1): `get_flag/2` and `set_flag/2`, the two
# built-ins `flag/3` (boot/syspred.pl) is written over, and the table they read: `GD->flags.table`, a hash table of
# the key's word to a `struct flag`, here `gd.flags_table` (src/pl-global.jl) of `flag{T}` (src/pl-incl.jl).
#
# NOT PORTED: `initFlags` and `cleanupFlags` (the table is made empty by the database's constructor, src/pl-setup.jl, and
# dies with it), `freeFlagSymbol` and `freeFlagValue` (`PL_unregister_atom` of an atom value: the kernel has no atom GC),
# `pl_current_flag` (`current_flag/1`, a `FRG` entry of pl-ext.c: not wanted yet).
# DIVERGES (file-wide): the `PL_LOCK(L_FLAG)` pairs are left out (the kernel runs one thread); no `PL_register_atom`
# (no atom GC).
# Source at af9e2e7e (swipl 10.1.21 development) differs in two places, neither ported: `lookupFlag` also makes a
# functor key permanent (`else if ( isFunctor(key) ) permanentFunctor((functor_t)key)`: the kernel has no functor GC),
# and `set_flag/2` raises `int_range_error(value, ATOM_int64_t, false)` for a big integer where the pin raises
# `representation_error(int64_t)`.

# PORT: pl-flag.c lookupFlag as lookupFlagEntry
# DIVERGES: the database is the argument (`GD->flags.table`); named apart from pl-prologflag.c's `lookupFlag`
# (src/os/pl-prologflag.jl), which has the same signature on the Prolog flags; a new flag's atom value is `none`
# (upstream leaves the union at 0, the integer, which is the type of the new flag); no `PL_register_atom`, and no
# `addHTableWP` race (one thread: `addHTableWP` returns the new flag itself).
"The `flag` of the key word `key`, made with the integer value 0 when there is none (pl-flag.c `lookupFlag`)."
function lookupFlagEntry(gd::PL_global_data{T}, key::word)::flag{T} where {T}
    of = get(gd.flags_table, key, nothing)              # lookupHTableWP(GD->flags.table, key)
    of === nothing || return of
    f = flag{T}(key, FLG_INTEGER, mk_sym(T, :none), Int64(0), 0.0)  # f->key = key; type = FLG_INTEGER; value.i = 0
    gd.flags_table[key] = f                             # addHTableWP(GD->flags.table, key, f)
    return f
end

# PORT: pl-flag.c get_flag as pl_get_flag2_va
# (PRED_IMPL("get_flag", 2, get_flag, 0), pl-flag.c at the pin 18168e62; unchanged at af9e2e7e)
# DIVERGES: see the file's comment (no `PL_LOCK(L_FLAG)`).
"`get_flag(+Key, -Value)`: the value of the flag `Key`, 0 when it has none yet (pl-flag.c)."
function pl_get_flag2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    name = PL__t0                                       # term_t name  = A1
    value = PL__t0 + 1                                  # term_t value = A2

    key = getKeyEx(ld, name)                            # if ( !getKeyEx(name, &key) ) return false
    key === nothing && return FFALSE
    f = lookupFlagEntry(gd, key)                        # f = lookupFlag(key)
    rc = if f.type == FLG_ATOM
        PL_unify_atom(ld, value, f.a)                   # PL_unify_atom(value, f->value.a)
    elseif f.type == FLG_INTEGER
        PL_unify_int64(ld, value, f.i)                  # PL_unify_int64(value, f->value.i)
    else
        @assert f.type == FLG_FLOAT                     # default: rc = false; assert(0)
        PL_unify_float(ld, value, f.f)                  # PL_unify_float(value, f->value.f)
    end
    return rc ? FTRUE : FFALSE
end

# PORT: pl-flag.c set_flag as pl_set_flag2_va
# (PRED_IMPL("set_flag", 2, set_flag, 0), pl-flag.c at the pin 18168e62; af9e2e7e: see the file's comment)
# DIVERGES: see the file's comment (no `PL_LOCK(L_FLAG)`, no `freeFlagValue`); `PL_error(NULL, 0, NULL, ...)` is
# `PL_error(ld, ERR_REPRESENTATION, int64_t)`, whose context names no predicate; the number arms are `_set_flag_number`, over
# the pooled number `n` the C function holds as a local.
"`set_flag(+Key, +Value)`: set the flag `Key` to an atom, an integer (in the `int64_t` range) or a float (pl-flag.c)."
function pl_set_flag2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    name = PL__t0                                       # term_t name  = A1
    value = PL__t0 + 1                                  # term_t value = A2

    key = getKeyEx(ld, name)                            # if ( !getKeyEx(name, &key) ) return false
    key === nothing && return FFALSE
    f = lookupFlagEntry(gd, key)                        # f = lookupFlag(key)

    a = PL_get_atom(ld, value)                          # PL_get_atom(value, &a)
    if a !== nothing
        f.type = FLG_ATOM                               # freeFlagValue(f); f->type = FLG_ATOM
        f.a = a                                         # f->value.a = a; PL_register_atom(a)
        return FTRUE
    end
    n = _number_alloc!(ld)                              # number n
    rc = _set_flag_number(ld, f, value, n)
    _number_free!(ld, 1)                                # n is released once, here
    return rc ? FTRUE : FFALSE
end

# PORT: pl-flag.c set_flag as _set_flag_number
# DIVERGES: the `else if ( PL_get_number(value, &n) )` and the `type_error:` arms of upstream's `set_flag`, over the pooled number
# `n` of the caller. `V_INTEGER` is the `Int64` range (src/pl-gmp.jl), the C `V_INTEGER`'s own.
"The number and error arms of `set_flag/2` on the flag `f` and the pooled number `n` (pl-flag.c)."
function _set_flag_number(
    ld::PL_local_data{T}, f::flag{T}, value::term_t, n::number
)::Bool where {T}
    if PL_get_number(ld, value, n)                      # else if ( PL_get_number(value, &n) )
        if n.type === V_INTEGER                         # case V_INTEGER:
            f.type = FLG_INTEGER                        # f->type = FLG_INTEGER
            f.i = n.i                                   # f->value.i = n.value.i
            return true
        elseif n.type === V_MPZ                         # case V_MPZ:
            return PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :int64_t))
        elseif n.type === V_FLOAT                       # case V_FLOAT:
            f.type = FLG_FLOAT                          # f->type = FLG_FLOAT
            f.f = n.f                                   # f->value.f = n.value.f
            return true
        end                                             # V_MPQ and default: goto type_error
    end
    return PL_error(ld, "flag", 3, "", ERR_TYPE, mk_sym(T, :flag_value), value)  # type_error:
end

# PORT: pl-flag.c BeginPredDefs as PL_predicates_from_flag
# DIVERGES: `PRED_DEF` ors in `PL_FA_VARARGS`.
"pl-flag.c's registration table (`BeginPredDefs(flag)`): `get_flag/2` and `set_flag/2`."
const PL_predicates_from_flag = (
    PL_extension("get_flag", 2, pl_get_flag2_va, PL_FA_VARARGS),
    PL_extension("set_flag", 2, pl_set_flag2_va, PL_FA_VARARGS)
)
