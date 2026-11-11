# UPSTREAM: swipl-devel src/os/pl-tai.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2021, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# TIME AND DATE (pl-tai.c), TAI1: `stamp_date_time/3`, `date_time_stamp/2`, `format_time/3` and `format_time/4`, on the
# libtai pieces of src/os/pl-libtai.jl. The kernel has no libc wrapper for the local time: the parts that need the host
# (`localtime_r`, `mktime`, `strftime`, `asctime_r`, `mbstowcs`, `tzset`, the variables `timezone` and `tzname`) are
# `ccall`s to libc, each confined to a named helper below (`PL_localtime_r`, `_c_mktime`, `_c_strftime`, `_c_asctime_r`,
# `_c_mbstowcs`, `do_tzset`, `tz_offset`, `tz_name`), so a platform without one can be refused there. UNTESTED: written
# without a compile (TAI1 writer, edit-only).
#
# DIVERGES (the design changes, all of them):
#   * `do_tzset` calls `tzset` each time and `tz_name_as_atom` keeps no cache: upstream's `GD->date.tz_initialized` and its
#     static atoms are process state, which tools/lint_globals.jl refuses at module scope. `tzset` is idempotent, so the
#     answers differ only if `TZ` changed since the first call.
#   * `struct tm` is `CTm` (the glibc layout, a mutable struct handed to libc as `Ref{CTm}`), `struct ftm` the mutable
#     struct `ftm`; a `time_t` is an `Int` (64-bit platforms: upstream's 32-bit `stime_t` branch is Windows only).
#   * `PL_unify_term` is a `PL_unify_functor` and one unify per argument (`_unify_date9`), in upstream's order.
#   * `Sfputs`/`Sfprintf` are a `Sputcode` loop (`_out_string`); `%.Nf` goes through `_fmt_c_printf_float`.
#   * a C `(int)`/`(long)` cast of a double that is out of range is the x86 answer (`typemin`), `_c_int32`, `_c_int64`.

# PORT: pl-tai.c TAI_UTC_OFFSET
"The TAI second count of 1970-01-01 00:00:00 UTC (pl-tai.c)."
const TAI_UTC_OFFSET = 4611686018427387914

# PORT: pl-tai.c HAS_STAMP
"`ftm.flags` bit: `stamp` is filled (pl-tai.c)."
const HAS_STAMP = 1
# PORT: pl-tai.c HAS_WYDAY
"`ftm.flags` bit: the week day and year day are filled (pl-tai.c)."
const HAS_WYDAY = 2
# PORT: pl-tai.c NO_UTC_OFFSET
"`ftm.utcoff` when the date term gave no offset (pl-tai.c)."
const NO_UTC_OFFSET = 2147483647

# ── struct tm and struct ftm ─────────────────────────────────────────────────────────────────────────

# ORIGINAL: glibc's `struct tm` on x86-64 Linux: nine `int`s, then `tm_gmtoff` (long) and `tm_zone` (const char *).
"A C `struct tm` (glibc layout), the argument of `localtime_r`, `mktime`, `strftime` and `asctime_r`."
mutable struct CTm
    tm_sec::Int32
    tm_min::Int32
    tm_hour::Int32
    tm_mday::Int32
    tm_mon::Int32
    tm_year::Int32
    tm_wday::Int32
    tm_yday::Int32
    tm_isdst::Int32
    tm_gmtoff::Int
    tm_zone::Ptr{UInt8}
end
CTm() = CTm(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, Ptr{UInt8}(0))

# PORT: pl-tai.c struct ftm
# DIVERGES: `tzname` is the text of the atom (or `nothing`), see the header.
"A `floating` version of the system `struct tm` (pl-tai.c): `tm`, the float seconds, the UTC offset, the zone name, DST, the stamp and the `flags` of the fields filled."
mutable struct ftm
    tm::CTm                                                 # System time structure
    sec::Float64                                            # float version of tm.tm_sec
    utcoff::Int                                             # offset to UTC (seconds)
    tzname::Union{Nothing, String}                          # Name of timezone
    isdst::Int                                              # Daylight saving time
    stamp::Float64                                          # Time stamp (sec since 1970-1-1)
    flags::Int                                              # Filled fields
end
ftm() = ftm(CTm(), 0.0, 0, nothing, 0, 0.0, 0)

# ── C casts and the libc calls ───────────────────────────────────────────────────────────────────────

# ORIGINAL: C's `(int64_t)x` of a double on x86-64 (`cvttsd2si`): truncation; NaN and out of range give INT64_MIN.
"`(int64_t)x` as the x86-64 hardware does it."
function _c_int64(x::Float64)::Int
    (isfinite(x) && x >= -9.223372036854775808e18 && x < 9.223372036854775808e18) || return typemin(Int)
    return unsafe_trunc(Int, x)
end
# ORIGINAL: C's `(int)x` of a double on x86-64: truncation; NaN and out of range give INT_MIN.
"`(int)x` as the x86-64 hardware does it."
function _c_int32(x::Float64)::Int32
    (isfinite(x) && x > -2147483649.0 && x < 2147483648.0) || return typemin(Int32)
    return unsafe_trunc(Int32, x)
end

# PORT: pl-os.c PL_localtime_r
# DIVERGES: libc's `localtime_r` through `ccall` (upstream's `HAVE_LOCALTIME_R` branch); true when it filled `tm`.
"Fill `tm` with the local time of the Unix time `t` (pl-os.c)."
function PL_localtime_r(t::Int, tm::CTm)::Bool
    p = ccall((:localtime_r, LIBC), Ptr{CTm}, (Ref{Int64}, Ref{CTm}), t, tm)
    return p != Ptr{CTm}(0)
end

# ORIGINAL: libc's `mktime`: normalises `tm` in place and answers the Unix time, -1 on failure.
"`mktime(tm)`: normalise `tm` and answer the Unix time (-1 when it has none)."
_c_mktime(tm::CTm)::Int = ccall((:mktime, LIBC), Int64, (Ref{CTm},), tm)

# ORIGINAL: libc's `strftime` into a 256 byte buffer; the bytes written, up to the NUL (`buf[0]` is cleared first: C
# reads an unset buffer when `strftime` answers 0).
"`strftime(buf, 256, fmt, tm)`: the bytes it wrote."
function _c_strftime(fmt::String, tm::CTm)::Vector{UInt8}
    buf = zeros(UInt8, 256)
    ccall(
        (:strftime, LIBC), Csize_t, (Ptr{UInt8}, Csize_t, Cstring, Ref{CTm}), buf, 256, fmt, tm
    )
    n = findfirst(==(0x00), buf)
    return buf[1:(n - 1)]
end

# PORT: pl-os.c PL_asctime_r
# DIVERGES: libc's `asctime_r` through `ccall`; the 26 byte buffer is returned up to its NUL.
"`asctime_r(tm, buf)`: `Www Mmm dd hh:mm:ss yyyy\\n` as bytes (pl-os.c)."
function _c_asctime_r(tm::CTm)::Vector{UInt8}
    buf = zeros(UInt8, 64)
    ccall((:asctime_r, LIBC), Ptr{UInt8}, (Ref{CTm}, Ptr{UInt8}), tm, buf)
    n = findfirst(==(0x00), buf)
    return buf[1:(n - 1)]
end

# ORIGINAL: libc's `mbstowcs` over the multibyte text `bytes` (to at most `max` wide characters) in the process's
# locale: the code points, or `nothing` when `bytes` is not valid in that locale (C answers (size_t)-1).
"`mbstowcs(wbuf, bytes, max)`: the code points, `nothing` for an invalid sequence."
function _c_mbstowcs(bytes::Vector{UInt8}, max::Int)::Union{Nothing, Vector{Int}}
    src = push!(copy(bytes), 0x00)
    wbuf = zeros(Int32, max + 1)
    n = ccall((:mbstowcs, LIBC), Csize_t, (Ptr{Int32}, Ptr{UInt8}, Csize_t), wbuf, src, max)
    n == typemax(Csize_t) && return nothing
    return Int[Int(wbuf[i]) for i in 1:Int(n)]
end

# ── the time zone (pl-tai.c do_tzset, tz_offset, tz_name, tz_name_as_atom) ───────────────────────────

# PORT: pl-tai.c do_tzset
# DIVERGES: `tzset` each time (see the header).
"Initialise the C library's time zone data (pl-tai.c)."
function do_tzset()::Nothing
    ccall((:tzset, LIBC), Cvoid, ())
    return nothing
end

# PORT: pl-tai.c tz_offset
# DIVERGES: the `HAVE_VAR_TIMEZONE` branch (POSIX's variable `timezone`, seconds WEST of GMT) only.
"The offset from UTC in seconds, west positive (pl-tai.c)."
function tz_offset()::Int
    do_tzset()
    return Int(unsafe_load(cglobal((:timezone, LIBC), Clong)))
end

# PORT: pl-tai.c tz_name
# DIVERGES: `nothing` for the NULL pointer; the text is read as UTF-8 (`unsafe_string`).
"The name of the standard (`dst` 0) or the daylight saving time zone (pl-tai.c)."
function tz_name(dst::Int)::Union{Nothing, String}
    d = dst != 0 ? 1 : 0
    do_tzset()
    p = unsafe_load(cglobal((:tzname, LIBC), Ptr{UInt8}), d + 1)
    p == Ptr{UInt8}(0) && return nothing
    return unsafe_string(p)
end

# PORT: pl-tai.c tz_name_as_atom
# DIVERGES: no cache of the first answer (see the header); the name's text, `<unknown>` for NULL.
"The name of the zone of `dst` (> 0: daylight saving) as text (pl-tai.c)."
function tz_name_as_atom(dst::Int)::String
    str = tz_name(dst > 0 ? 1 : 0)
    return str === nothing ? "<unknown>" : str
end

# ── time stamps and the date terms ───────────────────────────────────────────────────────────────────

# ORIGINAL: the text of an atom for a comparison with a name (a blob has none).
"Is the atom `a` the symbol `name`?"
_atom_is(a::T, name::String)::Bool where {T} = !is_blob(a) && sym_text(a) == name

# PORT: pl-tai.c get_taia
# DIVERGES: the `taia` is the tuple `(sec, nano, seconds)`: its TAI second count, its nanoseconds and the float `*seconds`;
# `nothing` when `t` is no number.
"The TAI time of the time stamp `t` (a number of seconds since 1970-1-1) (pl-tai.c)."
function get_taia(
    ld::PL_local_data{T}, t::term_t, leapsecs::Vector{UInt64}
)::Union{Nothing, Tuple{UInt64, Int, Float64}} where {T}
    d = PL_get_float(ld, t)
    d === nothing && return nothing
    fp, ip = modf(d)
    if fp < 0
        fp += 1.0
        ip -= 1.0
    end
    sec = (_c_int64(ip) + TAI_UTC_OFFSET) % UInt64
    nano = _c_int64(fp * 1e9)
    sec = leapsecs_add(leapsecs, sec, false)
    return (sec, nano, d)
end

# PORT: pl-tai.c get_tz_arg
"Argument `i` of the date term `t` as the zone name: variable or `-` leave `tb.tzname` unset (pl-tai.c)."
function get_tz_arg(ld::PL_local_data{T}, i::Int, t::term_t, a::term_t, tb::ftm)::Bool where {T}
    _PL_get_arg(ld, i, t, a)
    if !PL_is_variable(ld, a)
        name = PL_get_atom_ex(ld, a)
        name === nothing && return false
        if !_atom_is(name, "-")
            tb.tzname = is_blob(name) ? "" : sym_text(name)
        end
    end
    return true
end

# PORT: pl-tai.c get_int_arg
# DIVERGES: the value, or `nothing` with the error raised.
"Argument `i` of the date term `t` as a C `int` (pl-tai.c)."
function get_int_arg(
    ld::PL_local_data{T}, i::Int, t::term_t, a::term_t
)::Union{Nothing, Int} where {T}
    _PL_get_arg(ld, i, t, a)
    return PL_get_integer_ex(ld, a)
end

# PORT: pl-tai.c get_voff_arg
# DIVERGES: the value, or `nothing` with the error raised.
"Argument `i` of the date term `t` as the UTC offset: a variable is `NO_UTC_OFFSET` (pl-tai.c)."
function get_voff_arg(
    ld::PL_local_data{T}, i::Int, t::term_t, a::term_t
)::Union{Nothing, Int} where {T}
    _PL_get_arg(ld, i, t, a)
    PL_is_variable(ld, a) && return NO_UTC_OFFSET
    return PL_get_long_ex(ld, a)
end

# PORT: pl-tai.c get_dst_arg
# DIVERGES: the value (1 `true`, 0 `false`, -1 `-`, -2 a variable), or `nothing` with the error raised.
"Argument `i` of the date term `t` as the DST flag (pl-tai.c)."
function get_dst_arg(
    ld::PL_local_data{T}, i::Int, t::term_t, a::term_t
)::Union{Nothing, Int} where {T}
    _PL_get_arg(ld, i, t, a)
    name = PL_get_atom(ld, a)
    if name !== nothing
        _atom_is(name, "true") && return 1
        _atom_is(name, "false") && return 0
        _atom_is(name, "-") && return -1
    elseif PL_is_variable(ld, a)
        return -2
    end
    b = PL_get_bool_ex(ld, a)                               # generate an error
    b === nothing && return nothing
    return b ? 1 : 0
end

# PORT: pl-tai.c get_v_float_arg
# DIVERGES: the value, or `nothing` (failure or error); `v` is a `Ref`.
"Argument `i` of the date term `t` as a float: while `v` holds, a variable is bound to `def` (pl-tai.c)."
function get_v_float_arg(
    ld::PL_local_data{T}, i::Int, t::term_t, a::term_t, v::Base.RefValue{Bool}, def::Float64
)::Union{Nothing, Float64} where {T}
    _PL_get_arg(ld, i, t, a)
    if PL_is_variable(ld, a) && v[]
        return PL_unify_float(ld, a, def) ? def : nothing
    end
    v[] = false
    return PL_get_float_ex(ld, a)
end

# PORT: pl-tai.c get_v_int_arg
# DIVERGES: the value, or `nothing` (failure or error); `v` is a `Ref`.
"Argument `i` of the date term `t` as an `int`: while `v` holds, a variable is bound to `def` (pl-tai.c)."
function get_v_int_arg(
    ld::PL_local_data{T}, i::Int, t::term_t, a::term_t, v::Base.RefValue{Bool}, def::Int
)::Union{Nothing, Int} where {T}
    _PL_get_arg(ld, i, t, a)
    if PL_is_variable(ld, a) && v[]
        return PL_unify_integer(ld, a, def) ? def : nothing
    end
    v[] = false
    return PL_get_integer_ex(ld, a)
end

# ORIGINAL: the `date/9` branch of get_ftm's chain of tests (`a && b && ...`), in upstream's order of arguments
# (1, 6, 5, 4, 3, 2, 7, 8, 9): true when every argument was read.
"Read the arguments of the `date/9` term `t` into `tb` (pl-tai.c get_ftm)."
function _get_date9(ld::PL_local_data{T}, t::term_t, tmp::term_t, tb::ftm)::Bool where {T}
    v = Ref(true)
    year = get_int_arg(ld, 1, t, tmp)
    year === nothing && return false
    tb.tm.tm_year = year % Int32
    sec = get_v_float_arg(ld, 6, t, tmp, v, 0.0)
    sec === nothing && return false
    tb.sec = sec
    minute = get_v_int_arg(ld, 5, t, tmp, v, 0)
    minute === nothing && return false
    tb.tm.tm_min = minute % Int32
    hour = get_v_int_arg(ld, 4, t, tmp, v, 0)
    hour === nothing && return false
    tb.tm.tm_hour = hour % Int32
    mday = get_v_int_arg(ld, 3, t, tmp, v, 1)
    mday === nothing && return false
    tb.tm.tm_mday = mday % Int32
    mon = get_v_int_arg(ld, 2, t, tmp, v, 1)
    mon === nothing && return false
    tb.tm.tm_mon = mon % Int32
    off = get_voff_arg(ld, 7, t, tmp)
    off === nothing && return false
    tb.utcoff = off
    get_tz_arg(ld, 8, t, tmp, tb) || return false
    dst = get_dst_arg(ld, 9, t, tmp)
    dst === nothing && return false
    tb.isdst = dst
    return true
end

# ORIGINAL: the `fixup:` label of get_ftm, shared by the `date/9` and the `date/3` branch (`date9` tells which).
"Normalise the fields read, find the UTC offset and the missing names of the date term `t` (pl-tai.c get_ftm)."
function _ftm_fixup(
    ld::PL_local_data{T}, t::term_t, tmp::term_t, tb::ftm, date9::Bool
)::Bool where {T}
    fp, ip = modf(tb.sec)
    if fp < 0.0
        fp += 1.0
        ip -= 1.0
    end

    tb.tm.tm_sec = _c_int32(ip)
    tb.tm.tm_year = (Int(tb.tm.tm_year) - 1900) % Int32     # 1900 based
    tb.tm.tm_mon = (Int(tb.tm.tm_mon) - 1) % Int32          # 0-based

    if tb.utcoff == NO_UTC_OFFSET
        if tb.tm.tm_isdst < 0                               # unknown DST
            if _c_mktime(tb.tm) == -1
                return PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :dst))
            end
            tb.flags |= HAS_WYDAY

            offset = tz_offset()
            if tb.tm.tm_isdst > 0
                offset -= 3600
            end
            tb.utcoff = offset

            if date9                                        # variable
                _PL_get_arg(ld, 7, t, tmp)
                PL_unify_integer(ld, tmp, tb.utcoff) || return false
            else
                tb.utcoff = offset
            end
        end

        if date9
            if tb.isdst == -2
                tb.isdst = Int(tb.tm.tm_isdst)
                _PL_get_arg(ld, 9, t, tmp)
                if tb.isdst < 0
                    PL_unify_atom(ld, tmp, mk_sym(T, Symbol("-"))) || return false
                else
                    PL_unify_bool(ld, tmp, tb.isdst != 0) || return false
                end
            end

            if tb.tzname === nothing
                tb.tzname = tz_name_as_atom(tb.isdst)
                _PL_get_arg(ld, 8, t, tmp)
                if PL_is_variable(ld, tmp) &&
                    !PL_unify_atom(ld, tmp, mk_sym(T, Symbol(tb.tzname)))
                    return false
                end
            end
        end
    end

    return true
end

# PORT: pl-tai.c get_ftm
# DIVERGES: the `ftm` is the answer, `nothing` for a failure or an error; a chain of arguments that failed falls through
# to `type_error(time, T)` as the C does (`PL_error` leaves an older exception alone), the failures after `fixup:` do not.
"The `ftm` of the date term `t`, `date(Y,M,D,H,Mn,S,Off,TZ,DST)` or `date(Y,M,D)`; unbound fields get their defaults and are bound (pl-tai.c)."
function get_ftm(ld::PL_local_data{T}, t::term_t)::Union{Nothing, ftm} where {T}
    tmp = PL_new_term_ref(ld)
    tb = ftm()
    date9 = PL_is_functor(ld, t, mk_sym(T, :date), 9)

    if date9
        if _get_date9(ld, t, tmp, tb)
            tb.tm.tm_isdst = (tb.isdst == -2 ? -1 : tb.isdst) % Int32
            return _ftm_fixup(ld, t, tmp, tb, true) ? tb : nothing   # `goto fixup`: its failures return as they are
        end
    elseif PL_is_functor(ld, t, mk_sym(T, :date), 3)
        y = get_int_arg(ld, 1, t, tmp)
        if y !== nothing
            tb.tm.tm_year = y % Int32
            m = get_int_arg(ld, 2, t, tmp)
            if m !== nothing
                tb.tm.tm_mon = m % Int32
                d = get_int_arg(ld, 3, t, tmp)
                if d !== nothing
                    tb.tm.tm_mday = d % Int32
                    tb.tm.tm_isdst = -1
                    tb.utcoff = NO_UTC_OFFSET
                    return _ftm_fixup(ld, t, tmp, tb, false) ? tb : nothing
                end
            end
        end
    end

    PL_error(ld, ERR_TYPE, mk_sym(T, :time), t)
    return nothing
end

# PORT: pl-tai.c cal_ftm
# DIVERGES: the leap-second table is an argument.
"Compute the fields `tb` lacks (`required` names those wanted) from its fields (pl-tai.c)."
function cal_ftm(tb::ftm, required::Int, leapsecs::Vector{UInt64})::Nothing
    missing_ = tb.flags ⊻ required

    if missing_ != 0                                        # we need something, so we always need the stamp
        ct = caltime(
            caldate(Int(tb.tm.tm_year) + 1900, Int(tb.tm.tm_mon) + 1, Int(tb.tm.tm_mday)),
            Int(tb.tm.tm_hour), Int(tb.tm.tm_min), Int(tb.tm.tm_sec), 0
        )
        tai = caltime_tai(ct, leapsecs)

        if (missing_ & HAS_WYDAY) != 0
            # Gets weekday and yday at UTC, so we compensate afterwards!
            wday, yday = caltime_utc(ct, tai, leapsecs)
            tb.tm.tm_wday = wday % Int32
            tb.tm.tm_yday = yday % Int32
            tb.flags |= HAS_WYDAY
        end

        tai += tb.utcoff % UInt64

        tai, _ = leapsecs_sub(leapsecs, tai)
        tb.stamp = Float64((tai % Int) - TAI_UTC_OFFSET)
        tb.stamp -= Float64(ct.second)
        tb.stamp += tb.sec
        tb.flags |= HAS_STAMP
    end
    return nothing
end

# ORIGINAL: `PL_unify_term(t, PL_FUNCTOR, FUNCTOR_date9, PL_LONG, year, PL_INT, month, ...)` of stamp_date_time/3, one unify
# per argument in order. `PL_INT` takes the low 32 bits of a long (a C vararg read as int), `offset` is cut so.
"Unify `t` with `date(Y, M, D, H, Mn, Sec, Off, TZ, DST)` (pl-tai.c stamp_date_time)."
function _unify_date9(
    ld::PL_local_data{T}, t::term_t, year::Int, month::Int, day::Int, hour::Int, minute::Int,
    sec::Float64, offset::Int, tz::String, dst::String
)::Bool where {T}
    PL_unify_functor(ld, t, mk_sym(T, :date), 9) || return false
    a = PL_new_term_ref(ld)
    _PL_get_arg(ld, 1, t, a)
    PL_unify_integer(ld, a, year) || return false
    _PL_get_arg(ld, 2, t, a)
    PL_unify_integer(ld, a, Int(month % Int32)) || return false
    _PL_get_arg(ld, 3, t, a)
    PL_unify_integer(ld, a, Int(day % Int32)) || return false
    _PL_get_arg(ld, 4, t, a)
    PL_unify_integer(ld, a, Int(hour % Int32)) || return false
    _PL_get_arg(ld, 5, t, a)
    PL_unify_integer(ld, a, Int(minute % Int32)) || return false
    _PL_get_arg(ld, 6, t, a)
    PL_unify_float(ld, a, sec) || return false
    _PL_get_arg(ld, 7, t, a)
    PL_unify_integer(ld, a, Int(offset % Int32)) || return false
    _PL_get_arg(ld, 8, t, a)
    PL_unify_atom(ld, a, mk_sym(T, Symbol(tz))) || return false
    _PL_get_arg(ld, 9, t, a)
    return PL_unify_atom(ld, a, mk_sym(T, Symbol(dst)))
end

# PORT: pl-tai.c stamp_date_time
# (PRED_IMPL("stamp_date_time", 3, stamp_date_time, 0))
# DIVERGES: the `unixt` representability test is dropped (a 64-bit `time_t` holds every `int64_t`).
"`stamp_date_time(+Stamp, -DateTime, +TimeZone)`: `DateTime` is `date(Y,M,D,H,Mn,S,Off,TZ,DST)` for the time stamp, `TimeZone` `local`, `'UTC'` or an offset in seconds (pl-tai.c)."
function pl_stamp_date_time3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    leapsecs = leapsecs_init()
    ta = get_taia(ld, A1, leapsecs)

    if ta !== nothing
        tsec, nano, argsec = ta
        ct = caltime()
        sec = 0.0
        utcoffset = 0
        done = false
        tzatom = "-"
        dstatom = "-"

        alocal = PL_get_atom(ld, A3)
        if alocal !== nothing
            if _atom_is(alocal, "local")
                utcoffset = tz_offset()

                tai, _ = leapsecs_sub(leapsecs, tsec)
                ut64 = (tai % Int) - TAI_UTC_OFFSET
                unixt = ut64

                tm = CTm()
                PL_localtime_r(unixt, tm)
                ip_frac, _ = modf(argsec)
                sec = Float64(tm.tm_sec) + ip_frac
                ct.date.year = Int(tm.tm_year) + 1900
                ct.date.month = Int(tm.tm_mon) + 1
                ct.date.day = Int(tm.tm_mday)
                ct.hour = Int(tm.tm_hour)
                ct.minute = Int(tm.tm_min)
                tzatom = tz_name_as_atom(Int(tm.tm_isdst))
                if tm.tm_isdst > 0
                    utcoffset -= 3600
                    dstatom = "true"
                else
                    dstatom = "false"
                end
                done = true
            elseif _atom_is(alocal, "UTC")
                utcoffset = 0
                tzatom = "UTC"
            else
                PL_error(ld, ERR_DOMAIN, mk_sym(T, :timezone), A3)
                return FFALSE
            end
        else
            off = PL_get_long_ex(ld, A3)
            off === nothing && return FFALSE
            utcoffset = off
        end

        if !done
            tsec -= utcoffset % UInt64
            caltime_utc(ct, tsec, leapsecs)
            sec = Float64(ct.second) + Float64(nano) / 1e9
        end

        return _unify_date9(
            ld, A2, ct.date.year, ct.date.month, ct.date.day, ct.hour, ct.minute, sec,
            utcoffset, tzatom, dstatom
        ) ? FTRUE : FFALSE
    end

    # time_stamp
    PL_error(ld, ERR_TYPE, mk_sym(T, :float), A1)
    return FFALSE
end

# PORT: pl-tai.c date_time_stamp
# (PRED_IMPL("date_time_stamp", 2, date_time_stamp, 0))
"`date_time_stamp(+DateTime, -Stamp)`: the time stamp of a `date/9` or `date/3` term (pl-tai.c)."
function pl_date_time_stamp2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    tb = get_ftm(ld, PL__t0)
    tb === nothing && return FFALSE
    cal_ftm(tb, HAS_STAMP, leapsecs_init())
    return PL_unify_float(ld, PL__t0 + 1, tb.stamp) ? FTRUE : FFALSE
end

# PORT: pl-tai.c BeginPredDefs
# DIVERGES: appended last in `_PRED_TABLES` (src/pl-ext.jl), so the dispatch indices of the earlier tables stay as they were.
"pl-tai.c's registration table (`BeginPredDefs(tai)`)."
const PL_predicates_from_tai = (
    PL_extension("stamp_date_time", 3, pl_stamp_date_time3_va, PL_FA_VARARGS),
    PL_extension("date_time_stamp", 2, pl_date_time_stamp2_va, PL_FA_VARARGS),
)
