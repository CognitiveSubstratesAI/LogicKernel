# UPSTREAM: swipl-devel src/libtai/caldate_mjd.c @ 18168e629eab
# UPSTREAM: swipl-devel src/libtai/caldate_fmjd.c @ 18168e629eab
# UPSTREAM: swipl-devel src/libtai/caltime_tai.c @ 18168e629eab
# UPSTREAM: swipl-devel src/libtai/caltime_utc.c @ 18168e629eab
# UPSTREAM: swipl-devel src/libtai/leapsecs_init.c @ 18168e629eab
# UPSTREAM: swipl-devel src/libtai/leapsecs_read.c @ 18168e629eab
# UPSTREAM: swipl-devel src/libtai/leapsecs_add.c @ 18168e629eab
# UPSTREAM: swipl-devel src/libtai/leapsecs_sub.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: libtai 0.60, D. J. Bernstein (public domain), as vendored by SWI-Prolog
#
# THE LIBTAI PIECES pl-tai.c NEEDS (TAI1): the calendar-date to Modified-Julian-Day conversions, the calendar-time to
# TAI conversions and the leap-second table. A `struct tai` is its 64-bit second count here (a `UInt64`, as in C:
# every sum wraps); `struct taia` is that count plus the nanoseconds, kept as two values by pl-tai.jl. UNTESTED:
# written without a compile (TAI1 writer, edit-only).
#
# DIVERGES (all of it): a C out-parameter is a return value (`caltime_tai` returns the `UInt64`, `caltime_utc` and
# `caldate_frommjd` return `(wday, yday)`; the NULL pointer variants of `pwday`/`pyday` are not written: pl-tai.c always
# passes both). The leap-second table is a value, not module state (tools/lint_globals.jl refuses module-level mutable
# state): `leapsecs_init()` reads `/etc/leapsecs.dat` (the file C reads) and answers the table, uncached, and every
# function that consults it takes it as its first argument; an unreadable or missing file is an empty table (in C a
# read failure makes `leapsecs_add` and `leapsecs_sub` do nothing, which an empty table does as well).

# PORT: libtai/caldate.h struct caldate
"A calendar date (libtai `struct caldate`): `year` (long), `month` 1-12 and `day` 1-31 (int)."
mutable struct caldate
    year::Int
    month::Int
    day::Int
end
caldate() = caldate(0, 0, 0)

# PORT: libtai/caltime.h struct caltime
"A calendar time (libtai `struct caltime`): a date, `hour`, `minute`, `second` (int) and `offset` in minutes (long)."
mutable struct caltime
    date::caldate
    hour::Int
    minute::Int
    second::Int
    offset::Int
end
caltime() = caltime(caldate(), 0, 0, 0, 0)

# PORT: libtai/caldate_mjd.c times365
"The days of 0 to 3 whole years of 365 days (libtai caldate_mjd.c)."
const _TIMES365 = (0, 365, 730, 1095)
# PORT: libtai/caldate_mjd.c times36524
"The days of 0 to 3 whole centuries (libtai caldate_mjd.c)."
const _TIMES36524 = (0, 36524, 73048, 109572)
# PORT: libtai/caldate_mjd.c montab
"The days before each month, counted from March (libtai caldate_mjd.c)."
const _MONTAB = (0, 31, 61, 92, 122, 153, 184, 214, 245, 275, 306, 337)

# PORT: libtai/caldate_mjd.c caldate_mjd
"The Modified Julian Day number of the calendar date `cd` (libtai caldate_mjd.c); C `/` and `%` truncate, `÷` and `%` do the same."
function caldate_mjd(cd::caldate)::Int
    d = cd.day - 678882
    m = cd.month - 1
    y = cd.year
    d += 146097 * (y ÷ 400)
    y %= 400
    if m >= 2
        m -= 2
    else
        m += 10
        y -= 1
    end
    y += (m ÷ 12)
    m %= 12
    if m < 0
        m += 12
        y -= 1
    end
    d += _MONTAB[m + 1]
    d += 146097 * (y ÷ 400)
    y %= 400
    if y < 0
        y += 400
        d -= 146097
    end
    d += _TIMES365[(y & 3) + 1]
    y >>= 2
    d += 1461 * (y % 25)
    y = y ÷ 25
    d += _TIMES36524[(y & 3) + 1]
    return d
end

# PORT: libtai/caldate_fmjd.c caldate_frommjd
"Fill `cd` with the calendar date of the Modified Julian Day `day` and answer `(weekday, yearday)` (libtai caldate_fmjd.c)."
function caldate_frommjd(cd::caldate, day::Int)::Tuple{Int, Int}
    year = day ÷ 146097
    day %= 146097
    day += 678881
    while day >= 146097
        day -= 146097
        year += 1
    end
    # year * 146097 + day - 678881 is MJD; 0 <= day < 146097
    # 2000-03-01, MJD 51604, is year 5, day 0
    wday = (day + 3) % 7
    year *= 4
    if day == 146096
        year += 3
        day = 36524
    else
        year += day ÷ 36524
        day %= 36524
    end
    year *= 25
    year += day ÷ 1461
    day %= 1461
    year *= 4
    yday = day < 306 ? 1 : 0
    if day == 1460
        year += 3
        day = 365
    else
        year += day ÷ 365
        day %= 365
    end
    yday += day
    day *= 10
    month = (day + 5) ÷ 306
    day = (day + 5) % 306
    day = day ÷ 10
    if month >= 10
        yday -= 306
        year += 1
        month -= 10
    else
        yday += 59
        month += 2
    end
    cd.year = year
    cd.month = month + 1
    cd.day = day + 1
    return (wday, yday)
end

# ── the leap-second table (leapsecs_*.c) ─────────────────────────────────────────────────────────

# PORT: libtai/leapsecs_read.c leapsecs_read
# DIVERGES: `open`/`fstat`/`read` is `read(file)`, and the table is the answer, not the global `leapsecs`. A file that
# cannot be read gives an empty table (C: -1 for a failure other than ENOENT, which leaves `leapsecs_add` and
# `leapsecs_sub` with nothing to do, as an empty table does). The entries are `tai_unpack`ed: 8 bytes, big endian; a
# trailing partial entry is dropped.
"The leap-second table `file` holds: TAI second counts, ascending; empty when the file is missing or unreadable (libtai leapsecs_read.c)."
function leapsecs_read(file::String)::Vector{UInt64}
    bytes = try
        read(file)
    catch
        return UInt64[]
    end
    n = length(bytes) ÷ 8
    t = Vector{UInt64}(undef, n)
    for i in 1:n
        u = UInt64(0)
        for k in 1:8
            u = (u << 8) | UInt64(bytes[(i - 1) * 8 + k])
        end
        t[i] = u
    end
    return t
end

# PORT: libtai/leapsecs_init.c leapsecs_init
# DIVERGES: not cached (no `flaginit`), and the table is the answer (see the header).
"The leap-second table of `/etc/leapsecs.dat` (libtai leapsecs_init.c)."
leapsecs_init()::Vector{UInt64} = leapsecs_read("/etc/leapsecs.dat")

# PORT: libtai/leapsecs_add.c leapsecs_add
"Add the leap seconds of `leapsecs` before the TAI second count `x` to it; `hit` leaves a second that is itself a leap second (libtai leapsecs_add.c)."
function leapsecs_add(leapsecs::Vector{UInt64}, x::UInt64, hit::Bool)::UInt64
    u = x
    for l in leapsecs
        u < l && break
        if !hit || (u > l)
            u += UInt64(1)
        end
    end
    return u
end

# PORT: libtai/leapsecs_sub.c leapsecs_sub
"Subtract the leap seconds of `leapsecs` from the TAI second count `x`: `(count, 1)` when `x` is a leap second itself, else `(count, 0)` (libtai leapsecs_sub.c)."
function leapsecs_sub(leapsecs::Vector{UInt64}, x::UInt64)::Tuple{UInt64, Int}
    u = x
    s = 0
    for l in leapsecs
        u < l && break
        s += 1
        u == l && return (u - (s % UInt64), 1)
    end
    return (u - (s % UInt64), 0)
end

# ── calendar time and TAI (caltime_*.c) ──────────────────────────────────────────────────────────

# PORT: libtai/caltime_tai.c caltime_tai
"The TAI second count of the calendar time `ct`, leap seconds from `leapsecs` (libtai caltime_tai.c); the sum wraps as the C `uint64_t` one does."
function caltime_tai(ct::caltime, leapsecs::Vector{UInt64})::UInt64
    day = caldate_mjd(ct.date)
    s = ct.hour * 60 + ct.minute
    s = (s - ct.offset) * 60 + ct.second
    x = (day % UInt64) * UInt64(86400) + UInt64(4611686014920671114) + (s % UInt64)
    return leapsecs_add(leapsecs, x, ct.second == 60)
end

# PORT: libtai/caltime_utc.c caltime_utc
"Fill `ct` with the UTC calendar time of the TAI second count `t`, leap seconds from `leapsecs` (the offset becomes 0) and answer `(weekday, yearday)` (libtai caltime_utc.c)."
function caltime_utc(ct::caltime, t::UInt64, leapsecs::Vector{UInt64})::Tuple{Int, Int}
    t2, leap = leapsecs_sub(leapsecs, t)
    u = t2
    u += UInt64(58486)
    s = Int(u % UInt64(86400))
    ct.second = (s % 60) + leap
    s = s ÷ 60
    ct.minute = s % 60
    s = s ÷ 60
    ct.hour = s
    u = u ÷ UInt64(86400)
    wy = caldate_frommjd(ct.date, (u % Int) - 53375995543064)
    ct.offset = 0
    return wy
end
