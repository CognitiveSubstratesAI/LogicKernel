# UPSTREAM: swipl-devel src/pl-sys.c @ cbf4e1896275
# UPSTREAM: swipl-devel src/os/pl-ctype.c @ cbf4e1896275
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
#
# CT1a: setlocale/3 (pl-ctype.c) is here as well: the boot's `os_user_lang` (boot/messages.pl) calls it, and the file of its
# upstream, src/os/pl-ctype.jl, is loaded before the FLI that a predicate needs. Its category table is in that file.

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

# ORIGINAL (CT1a): `PL_get_chars(t, &s, CVT_ATOM|CVT_EXCEPTION)` — the text of an atom as the bytes of a C string, as
# pl-ctype.c's setlocale/3 reads it: ISO Latin-1 (no `REP_*` flag), so a character above 0xFF raises
# `representation_error(encoding)`; the string ends at its first NUL; a term that is not an atom raises the error
# (`type_error(atom, …)`, `instantiation_error`) and answers `nothing`.
"The Latin-1 bytes of the atom term reference `t` holds (`CVT_ATOM|CVT_EXCEPTION`), or `nothing` after the error."
function _ctype_chars(ld::PL_local_data{T}, t::term_t)::Union{Nothing, String} where {T}
    txt = PL_get_text(ld, t, CVT_ATOM | CVT_EXCEPTION)
    txt === nothing && return nothing
    b = UInt8[]
    for c in text_string(txt)
        if UInt32(c) > 0xff
            PL_error(
                ld, "", 0, "cannot represent text using encoding iso_latin_1",
                ERR_REPRESENTATION, mk_sym(T, :encoding)
            )
            return nothing
        end
        push!(b, UInt8(c))
    end
    i = findfirst(==(0x00), b)
    i === nothing || resize!(b, i - 1)
    return String(b)
end

# ORIGINAL (CT1a): libc's `setlocale(category, locale)` through `ccall` (as `Setenv`, src/os/pl-os.jl); `locale`
# `nothing` is the NULL query. The answer is copied at once (libc's buffer lives until the next call) and `errno` read
# before anything else runs.
# DIVERGES (representation only; owner: none, platform behaviour; measured, glibc 2.39): upstream tests `errno == ENOENT` (src/os/pl-ctype.c:938) after a failed `setlocale(3)`, but glibc sets ENOENT only the
# FIRST time it fails to find a locale name and leaves `errno` untouched on every later try of that name (a negative cache), so
# upstream's answer for a repeated unknown name rests on whatever errno held before (a C program that sets `errno = 0` first
# sees `0` the second time). The kernel clears `errno` before the call and reads a failure that left it 0 as the not-found
# case (ENOENT): `existence_error(locale, Name)` every time, as swipl 10.1.19 answers in the .out. A failure with another
# errno (EINVAL for a name of 5000 characters) stays `system_error`.
"`(name, errno)`: libc's answer of `setlocale(category, locale)` — `nothing` when it fails — and the `errno` it left."
function _libc_setlocale(
    category::Cint, locale::Union{Nothing, String}
)::Tuple{Union{Nothing, String}, Int}
    Base.Libc.errno(0)
    p = if locale === nothing
        ccall((:setlocale, LIBC), Ptr{UInt8}, (Cint, Ptr{UInt8}), category, C_NULL)
    else
        ccall((:setlocale, LIBC), Ptr{UInt8}, (Cint, Cstring), category, locale)
    end
    e = Int(Base.Libc.errno())
    p == C_NULL && return (nothing, e)
    return (unsafe_string(p), e)
end

# PORT: pl-ctype.c setlocale as pl_setlocale3_va
# (PRED_IMPL("setlocale", 3, setlocale, 0))
# DIVERGES: the old locale is an atom of its UTF-8 text; no `CMP_ERROR` from the comparison (the kernel's compare
# raises nothing, src/pl-prims.jl); a failed query (libc answers NULL) fails. LEFT to the port of pl-locale.c:
# `updateLocale(category, locale)`, which updates the default locale object (`O_LOCALE`: locale_create/3 and its rows).
"`setlocale(+Category, -Old, +New)`: unify `Old` with the locale of `Category` and set it to `New` unless `Old` equals `New`; an unbound `New` only queries (pl-ctype.c)."
function pl_setlocale3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    what = _ctype_chars(ld, A1)
    what === nothing && return FFALSE
    locale::Union{Nothing, String} = nothing
    if !PL_is_variable(ld, A3)
        locale = _ctype_chars(ld, A3)
        locale === nothing && return FFALSE
    end

    for lcp in lccats
        if lcp.name == what
            old, _ = _libc_setlocale(lcp.category, nothing)
            old === nothing && return FFALSE
            PL_unify_atom(ld, A2, mk_sym(T, Symbol(old))) || return FFALSE

            rc = PL_compare(ld, A2, A3)
            if rc != CMP_EQUAL
                r, e = _libc_setlocale(lcp.category, locale)
                if r === nothing
                    if e == ENOENT || e == 0    # DIVERGES: e == 0 is glibc's repeated not-found (_libc_setlocale)
                        PL_error(ld, ERR_EXISTENCE, mk_sym(T, :locale), A3)
                        return FFALSE
                    end
                    PL_error(ld, "", 0, MSG_ERRNO, ERR_SYSCALL, "setlocale", e)
                    return FFALSE
                end
            end

            return FTRUE
        end
    end

    PL_domain_error(ld, "category", A1)
    return FFALSE
end

# PORT: pl-ctype.c BeginPredDefs as PL_predicates_from_ctype
# DIVERGES: the ported entries (upstream's table also has char_type/2, code_type/2, downcase_atom/2, ...).
"pl-ctype.c's registration table (`BeginPredDefs(ctype)`): the ported entries."
const PL_predicates_from_ctype = (
    PL_extension("setlocale", 3, pl_setlocale3_va, PL_FA_VARARGS),
)
