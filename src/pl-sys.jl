# UPSTREAM: swipl-devel src/pl-sys.c @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2023, University of Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# SYSTEM PREDICATES (pl-sys.c), since Y1: the process environment — getenv/2, setenv/2, unsetenv/1 —
# the clock — get_time/1 — and sleep/1. They call the OS layer of src/os/pl-os.jl (`getenv3`, `Setenv`,
# `Unsetenv`, `WallTime`, `Pause`).
#
# NOT PORTED: shell/2 (`System`: running a command through the shell; not needed before the loader's
# `shell` callers, which no R2 step reaches).

# ORIGINAL (Y1): `PL_get_chars(t, &s, CVT_ALL|REP_FN|CVT_EXCEPTION)` — the text of an atom, a string, a number or
# a code list, as a `String`. A C string ends at its first NUL, so does this one; a conversion failure
# raises the error and answers `nothing`.
"The text the term reference `t` holds as pl-sys.c reads it (`CVT_ALL|CVT_EXCEPTION`), or `nothing` after the error."
function _sys_chars(ld::PL_local_data{T}, t::term_t)::Union{Nothing, String} where {T}
    txt = PL_get_text(ld, t, CVT_ALL | CVT_EXCEPTION)
    txt === nothing && return nothing
    s = text_string(txt)
    i = findfirst(==('\0'), s)
    return i === nothing ? s : s[1:prevind(s, i)]
end

# PORT: pl-sys.c getenv as pl_getenv2_va
# (PRED_IMPL("getenv", 2, getenv, 0))
# DIVERGES: the value comes whole from `getenv3` (no 1024-byte buffer and second call); an atom of its
# text (`PL_unify_chars(value, PL_ATOM|REP_FN, …)`, UTF-8).
"`getenv(+Name, -Value)`: the value of the environment variable `Name`, as an atom; fails when it is not set (pl-sys.c)."
function pl_getenv2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    n = _sys_chars(ld, A1)
    n === nothing && return FFALSE
    v = getenv3(n)
    v === nothing && return FFALSE
    return PL_unify_atom(ld, A2, mk_sym(T, Symbol(v))) ? FTRUE : FFALSE
end

# PORT: pl-sys.c setenv as pl_setenv2_va
# (PRED_IMPL("setenv", 2, setenv, 0))
"`setenv(+Name, +Value)`: set the environment variable `Name` to the text `Value` (pl-sys.c)."
function pl_setenv2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    n = _sys_chars(ld, A1)
    n === nothing && return FFALSE
    v = _sys_chars(ld, A2)
    v === nothing && return FFALSE
    return Setenv(ld, n, v) ? FTRUE : FFALSE
end

# PORT: pl-sys.c unsetenv as pl_unsetenv1_va
# (PRED_IMPL("unsetenv", 1, unsetenv, 0))
"`unsetenv(+Name)`: delete the environment variable `Name` (pl-sys.c)."
function pl_unsetenv1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    n = _sys_chars(ld, A1)
    n === nothing && return FFALSE
    return Unsetenv(ld, n) ? FTRUE : FFALSE
end

# PORT: pl-sys.c get_time as pl_get_time1_va
# (PRED_IMPL("get_time", 1, get_time, 0))
"`get_time(-Stamp)`: the time since the Epoch, as a float of seconds (pl-sys.c)."
function pl_get_time1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    return PL_unify_float(ld, A1, WallTime()) ? FTRUE : FFALSE
end

# PORT: pl-sys.c sleep as pl_sleep1_va
# (PRED_IMPL("sleep", 1, sleep, 0))
# DIVERGES: `sched_yield()` for a time of 0.0 is Julia's `yield()` (the scheduler's), see `Pause`.
"`sleep(+Seconds)`: suspend execution for `Seconds` (a number); a negative time succeeds at once (pl-sys.c)."
function pl_sleep1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    t = PL_get_float_ex(ld, A1)
    t === nothing && return FFALSE
    t < 0.0 && return FTRUE
    if t == 0.0                                 # HAVE_SCHED_YIELD
        yield()
        return FTRUE
    end
    return Pause(t) ? FTRUE : FFALSE
end

# PORT: pl-sys.c BeginPredDefs as PL_predicates_from_system
# DIVERGES: the ported entries (upstream's table also has `shell/2`).
"pl-sys.c's registration table (`BeginPredDefs(system)`): the ported entries."
const PL_predicates_from_system = (
    PL_extension("setenv", 2, pl_setenv2_va, PL_FA_VARARGS),
    PL_extension("unsetenv", 1, pl_unsetenv1_va, PL_FA_VARARGS),
    PL_extension("getenv", 2, pl_getenv2_va, PL_FA_VARARGS),
    PL_extension("get_time", 1, pl_get_time1_va, PL_FA_VARARGS),
    PL_extension("sleep", 1, pl_sleep1_va, PL_FA_VARARGS)
)
