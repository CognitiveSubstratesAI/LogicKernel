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

# ── file names (pl-os.c), since R2 LB2b ──────────────────────────────────────────────────────────
# The file-name functions os/pl-files.c calls, for the Unix branch (`__unix__`, not `O_XOS`, no drives,
# no NetBIOS names, no shares). NOT PORTED, as upstream's other branches: `O_HASDRIVES`, `O_NETBIOS`,
# `O_HASSHARES`, `O_XOS`, `O_CANONICALISE_DIRS`. A file name is a `String` (UTF-8, `REP_FN` in a UTF-8
# locale); `char *` buffers and their `buflen` are not kept (the length checks that remain are against
# `PATH_MAX`), the in-place algorithms run on a copy of the bytes.

# PORT: pl-os.c PrologPath
# DIVERGES: returns the name, or `nothing` where upstream returns NULL with `errno = ENAMETOOLONG` (a name
# of `len` bytes or more); `len` is `PATH_MAX`, upstream's caller passes `sizeof(buf)`.
"The Prolog form of the OS file name `p`: the name itself on Unix; `nothing` when it is `PATH_MAX` bytes or more (pl-os.c)."
PrologPath(p::String)::Union{Nothing, String} = ncodeunits(p) < PATH_MAX ? p : nothing

# PORT: pl-os.c OsPath
# DIVERGES: returns the name (upstream copies it into `buf`).
"The OS form of the Prolog file name `p`: the name itself on Unix (pl-os.c)."
OsPath(p::String)::String = p

# PORT: pl-os.c IsAbsolutePath
"Is `p` an absolute file name: it starts with `/` or is an IRI (pl-os.c)."
IsAbsolutePath(p::String)::Bool = startswith(p, '/') || file_name_is_iri(p) != 0

# ORIGINAL (LB2b): the byte at 0-based offset `i` of the padded buffer `b`, NUL outside it — what the C code reads
# through `in[1]`, `out[-1]` and `strlen`'s terminator.
_cfn_at(b::Vector{UInt8}, i::Int)::UInt8 = (i >= 0 && i < length(b)) ? b[i + 1] : 0x00

# PORT: pl-os.c canonicaliseFileName
# DIVERGES: takes and returns a `String` (upstream edits `path` in place; `buflen` only matters for drives).
# The C pointers `in`, `out`, `start` and the stack `saveb` of `out` positions are 0-based offsets into a
# NUL-padded copy of the bytes.
"""
    canonicaliseFileName(path) -> String

Remove redundant `/`, `./`, `x/../` and the like from `path`, an IRI's scheme and `://` kept (pl-os.c).
"""
function canonicaliseFileName(path::String)::String
    buf = Vector{UInt8}(codeunits(path))
    append!(buf, (0x00, 0x00, 0x00, 0x00))                      # the NUL and the look-ahead past it
    slash = UInt8('/')
    dot = UInt8('.')
    inp = 0
    out = 0
    start = 0
    sl = file_name_is_iri(path)
    if sl != 0
        inp += sl + 3
        out = inp
        start = inp
    end
    while _cfn_at(buf, inp) == slash && _cfn_at(buf, inp + 1) == dot &&
        _cfn_at(buf, inp + 2) == dot && _cfn_at(buf, inp + 3) == slash
        inp += 3
    end
    while _cfn_at(buf, inp) == dot && _cfn_at(buf, inp + 1) == slash
        inp += 2
    end
    if _cfn_at(buf, inp) == slash
        buf[out + 1] = slash
        out += 1
    end
    saveb = Int[out]
    while _cfn_at(buf, inp) != 0x00
        if _cfn_at(buf, inp) == slash
            while true                                          # again:
                _cfn_at(buf, inp) == 0x00 && break
                while _cfn_at(buf, inp + 1) == slash             # delete multiple /
                    inp += 1
                end
                if _cfn_at(buf, inp + 1) == dot
                    if _cfn_at(buf, inp + 2) == slash            # delete /./
                        inp += 2
                        continue
                    end
                    if _cfn_at(buf, inp + 2) == 0x00             # delete trailing /.
                        buf[out + 1] = 0x00
                        return String(buf[1:out])
                    end
                    if _cfn_at(buf, inp + 2) == dot &&
                        (_cfn_at(buf, inp + 3) == slash || _cfn_at(buf, inp + 3) == 0x00)
                        if _cfn_at(buf, out - 1) == dot && _cfn_at(buf, out - 2) == dot &&
                            (out - 2 == start || _cfn_at(buf, out - 3) == slash)
                            for k in 0:2                        # strncpy(out, in, 3)
                                buf[out + k + 1] = buf[inp + k + 1]
                            end
                            inp += 3
                            out += 3
                        else
                            if !isempty(saveb)                  # delete /foo/../
                                out = pop!(saveb)
                                inp += 3
                                if _cfn_at(buf, inp) == 0x00 && out > start + 1
                                    buf[out] = 0x00             # delete trailing /
                                    return String(buf[1:(out - 1)])
                                end
                                continue
                            elseif _cfn_at(buf, start) == slash && out == start + 1
                                inp += 3
                                continue
                            end
                        end
                    end
                end
                break
            end
            _cfn_at(buf, inp) != 0x00 && (inp += 1)
            if out > 0 && _cfn_at(buf, out - 1) != slash
                buf[out + 1] = slash
                out += 1
            end
            push!(saveb, out)
        else
            buf[out + 1] = buf[inp + 1]
            out += 1
            inp += 1
        end
    end
    return String(buf[1:out])
end

# PORT: pl-os.c utf8_path_lwr
# DIVERGES: returns the lower-cased name, or `nothing` where upstream returns NULL with `errno =
# ENAMETOOLONG` (the result would need `PATH_MAX` bytes or more); `lowercase(::Char)` (Julia's simple
# Unicode case mapping) stands in for `makeLowerW` (`PL_tolower`, src/pl-umap.c); only reached when the
# `file_name_case_handling` flag is not `case_sensitive` (the default on Linux is).
"The name `s` with every code point lower-cased, or `nothing` when it gets too long (pl-os.c)."
function utf8_path_lwr(s::String)::Union{Nothing, String}
    io = IOBuffer()
    o = 0
    for c in s
        lc = lowercase(c)
        w = ncodeunits(lc)
        o >= PATH_MAX - 6 && o + w >= PATH_MAX && return nothing
        write(io, lc)
        o += w
    end
    return String(take!(io))
end

# PORT: pl-os.c canonicalisePath
# DIVERGES: `ld` is an argument and the result is a `String`, or `nothing` after raising
# `representation_error(max_path_length)`; NOT PORTED: the `O_XOS` case-preserving branch.
"""
    canonicalisePath(ld, path) -> String or nothing

`canonicaliseFileName`, then lower-cased unless the `file_name_case_handling` flag says the file system is
case-sensitive (pl-os.c).
"""
function canonicalisePath(ld::PL_local_data{T}, path::String)::Union{Nothing, String} where {T}
    p = canonicaliseFileName(path)
    if !truePrologFlag(ld, PLFLAG_FILE_CASE)                    # not case-sensitive
        p = utf8_path_lwr(p)
        if p === nothing
            PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :max_path_length))
            return nothing
        end
    end
    return p
end

# PORT: pl-os.c BaseName
# DIVERGES: returns the name, or `nothing` where upstream returns NULL with `errno = ENAMETOOLONG`.
"""
    BaseName(f) -> String or nothing

The last component of `f`, trailing `/` ignored; `/` for `/` and `""` for `""` (pl-os.c).
"""
function BaseName(f::String)::Union{Nothing, String}
    b = codeunits(f)
    e = length(b)
    e == 0 && return ""
    while e > 0 && b[e] == UInt8('/')
        e -= 1
    end
    stop = e
    while e > 0 && b[e] != UInt8('/')
        e -= 1
    end
    # C: `e == end && *e == '/'`: only slashes (0-based `*e` is `b[e + 1]`)
    stop == e && b[e + 1] == UInt8('/') && return "/"
    stop - e + 1 <= PATH_MAX || return nothing
    return String(b[(e + 1):stop])
end

# PORT: pl-os.c DirName
# DIVERGES: returns the name, or `nothing` where upstream returns NULL with `errno = ENAMETOOLONG`; the
# in-place case (`dir == f`) is not kept.
"""
    DirName(f) -> String or nothing

The directory part of `f`: `.` when it has none, `/` for a name at the root, trailing `/` ignored (pl-os.c).
"""
function DirName(f::String)::Union{Nothing, String}
    b = codeunits(f)
    e = length(b)
    e == 0 && return "."
    while e > 0 && b[e] == UInt8('/')
        e -= 1
    end
    while e > 0 && b[e] != UInt8('/')
        e -= 1
    end
    while e > 0 && b[e] == UInt8('/')
        e -= 1
    end
    e == 0 && return b[1] == UInt8('/') ? "/" : "."
    e + 1 <= PATH_MAX || return nothing
    return String(b[1:e])
end
