# UPSTREAM: swipl-devel src/os/pl-os.c @ cbf4e1896275
# UPSTREAM: swipl-devel src/os/pl-os.h @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2023, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# THE OPERATING-SYSTEM LAYER (pl-os.c), since Y1: the clocks (`CpuTime`, `WallTime`),
# the process environment (`getenv3`, `Setenv`, `Unsetenv`) and `Pause`, which getenv/2, setenv/2,
# unsetenv/1, get_time/1, sleep/1 (src/pl-sys.jl) and statistics/2 (src/pl-prims.jl) call.
#
# The C library is called with `ccall`, as upstream calls it (`clock_gettime`, `setenv`, `unsetenv`): for
# the nanosecond clocks Julia does not give, and for the exact `errno` upstream reports. Each is on
# the unchecked-access allowlist (test/test_type_discipline.jl, "os/pl-os.jl ccall").
#
# NOT PORTED: the rest of pl-os.c (the file-name functions, `System`, the signals, the tmp-file
# registry `DeleteTemporaryFile` needs: no tmp_file/2 yet), the Windows and HAVE_TIMES branches, the
# `mitigate_spectre` flag's `clock_jitter` (the flag table, F1).

# ORIGINAL (Y1): the C library the clocks and the environment call (glibc's soname), as `LIBM` is libm's.
"The C library the OS layer calls (glibc's soname)."
const LIBC = "libc.so.6"

# PORT: pl-os.h CPU_USER
"Which CPU time `CpuTime` and `ThreadCPUTime` (src/pl-thread.jl) return: the user's (pl-os.h `CPU_USER`)."
const CPU_USER = 0
# PORT: pl-os.h CPU_SYSTEM
"Which CPU time `CpuTime` and `ThreadCPUTime` (src/pl-thread.jl) return: the system's (pl-os.h `CPU_SYSTEM`)."
const CPU_SYSTEM = 1

# ORIGINAL (Y1): Linux's `clockid_t` values (<time.h>), which `clock_gettime` takes.
"`CLOCK_REALTIME` (Linux)."
const CLOCK_REALTIME = Cint(0)
"`CLOCK_PROCESS_CPUTIME_ID` (Linux)."
const CLOCK_PROCESS_CPUTIME_ID = Cint(2)
"`CLOCK_THREAD_CPUTIME_ID` (Linux)."
const CLOCK_THREAD_CPUTIME_ID = Cint(3)

# ORIGINAL (Y1): `clock_gettime(clock, &ts)` and `timespec_to_double(ts)` (pl-os.c's macro) in one: the clock in
# seconds, `nothing` when the call fails. The `struct timespec` of 64-bit Linux is two `Int64`s.
"The time of the clock `clock` in seconds, or `nothing` when `clock_gettime` fails."
function _clock_gettime(clock::Cint)::Union{Nothing, Float64}
    ts = Ref((Int64(0), Int64(0)))
    rc = ccall((:clock_gettime, LIBC), Cint, (Cint, Ref{NTuple{2, Int64}}), clock, ts)
    rc == 0 || return nothing
    sec, nsec = ts[]
    return Float64(sec) + Float64(nsec) / 1000000000.0      # timespec_to_double
end

# PORT: pl-os.c CpuTime
# DIVERGES: the `CLOCK_PROCESS_CPUTIME_ID` branch only (the `times()` and wall-clock branches are for
# platforms without it); the user and system time are one (the clock's: `which` is not read), as
# upstream's. NOT PORTED: `clock_jitter` (the `mitigate_spectre` flag).
"""
    CpuTime(which) -> Float64

The CPU seconds the whole process has used (pl-os.c; `which` is `CPU_USER` or `CPU_SYSTEM`, which the
`clock_gettime` branch does not tell apart).
"""
function CpuTime(which::Int)::Float64
    t = _clock_gettime(CLOCK_PROCESS_CPUTIME_ID)                 # if clock_gettime(...) == 0
    return t === nothing ? 0.0 : t
end

# PORT: pl-os.c WallTime
# DIVERGES: NOT PORTED: `clock_jitter` (the `mitigate_spectre` flag).
"The seconds since the Epoch, to the nanosecond (`clock_gettime(CLOCK_REALTIME)`, pl-os.c)."
function WallTime()::Float64
    t = _clock_gettime(CLOCK_REALTIME)
    return t === nothing ? time() : t           # (no fallback upstream: the call cannot fail)
end

# PORT: pl-os.c getenv3
# DIVERGES: returns the value, or `nothing` where upstream returns `(size_t)-1` and copies into `buf`:
# Julia's `ENV` reads the process environment (`uv_os_getenv`). An empty name or one containing `=` is
# not found, as `getenv(3)` finds none.
"The value of the environment variable `name`, or `nothing` when it is not set (pl-os.c)."
function getenv3(name::String)::Union{Nothing, String}
    isempty(name) && return nothing
    return get(ENV, name, nothing)
end

# PORT: pl-os.c Setenv
# DIVERGES: `ld` is an argument, the error is raised in it; `setenv(3)` is `ccall`ed (not `putenv`), as
# upstream's HAVE_SETENV branch, so `errno` (`EINVAL` for an empty name or one with `=`) is upstream's.
"""
    Setenv(ld, name, value) -> Bool

Set the environment variable `name` to `value`; on failure raise `system_error` with the text of `errno`
(pl-os.c).
"""
function Setenv(ld::PL_local_data{T}, name::String, value::String)::Bool where {T}
    rc = ccall((:setenv, LIBC), Cint, (Cstring, Cstring, Cint), name, value, 1)
    if rc != 0
        return PL_error(ld, "", 0, MSG_ERRNO, ERR_SYSCALL, "setenv", Int(Base.Libc.errno()))
    end
    return true
end

# PORT: pl-os.c Unsetenv
# DIVERGES: `ld` is an argument, the error is raised in it; `unsetenv(3)` is `ccall`ed, as upstream's
# HAVE_UNSETENV branch without VOID_UNSETENV.
"""
    Unsetenv(ld, name) -> Bool

Delete the environment variable `name`; on failure raise `system_error` with the text of `errno` (pl-os.c).
"""
function Unsetenv(ld::PL_local_data{T}, name::String)::Bool where {T}
    rc = ccall((:unsetenv, LIBC), Cint, (Cstring,), name)
    if rc < 0
        return PL_error(
            ld, "", 0, MSG_ERRNO, ERR_SYSCALL, "unsetenv", Int(Base.Libc.errno())
        )
    end
    return true
end

# PORT: pl-os.c Pause
# DIVERGES: Julia's `sleep` (a timer on the scheduler, so other tasks run meanwhile and the resolution
# is the millisecond) where upstream calls `nanosleep` and handles `EINTR` (`PL_handle_signals`: no
# signals here). `nanosleep` fails with `EINVAL` for a time it cannot represent — a NaN, an infinity, or
# 2^63 seconds and more — and upstream then returns true at once, which is kept; a negative time
# succeeds without waiting.
"Suspend execution `t` seconds (pl-os.c `Pause`); true."
function Pause(t::Float64)::Bool
    t < 0.0 && return true
    t < 9.223372036854775807e18 || return true                  # NaN, ±Inf, too big: EINVAL
    sleep(min(t, 1.0e15))
    return true
end
