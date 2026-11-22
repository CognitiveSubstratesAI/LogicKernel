# UPSTREAM: swipl-devel src/os/pl-stream.c @ 18168e629eab
# UPSTREAM: swipl-devel src/os/SWI-Stream.h @ 18168e629eab
# UPSTREAM: swipl-devel src/os/pl-file.c @ 18168e629eab
# UPSTREAM: swipl-devel src/os/pl-locale.c @ 18168e629eab
# UPSTREAM: swipl-devel src/os/pl-utf8.h @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2026, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# PIN1 ledger (V10.1.20): re-cite only, no code change (cbf4e189..18168e62 compared, D-0447 Q1) — pl-stream.c: Sshare (87fc7589) is owner TH1 (docs/architecture.md, deferred owners); pl-file.c: set_eof_action, newline mode (cd67bb35, dfc1c55d, 4f259069) ported; shareStandardStream (87fc7589) is owner TH1 (docs/architecture.md, deferred owners).
# THE STREAM LAYER (since R1c; decided by the user, 2026-10-07: the IOSTREAM subset the reader and
# the writer call, over a Julia IO, UTF-8, with memory streams and the position record): an
# `IOSTREAM` with upstream's buffer discipline — the undo area before the buffer that
# `Speekcode` and `Sungetc` push back into, `Snpgetc`'s fast path, `S__fillbuf`, `S__flushbuf` —
# the position record (`IOPOS`: byte, character, line, display column, as `Supdatepos` keeps it),
# the error flags, and three function sets: memory files (`Sopenmem`), strings (`Sopen_string`)
# and a Julia `IO` (`Sopen_julia_io`, in place of the OS file functions).
#
# DIVERGES, the representation: a C pointer into a buffer is an INDEX into the stream's byte vector
# `mem` (`buffer == 0` for upstream's NULL buffer); the function table is `functions`, an enum over
# the function sets, and `handle` their record, where upstream holds function pointers and a
# `void *`; the open set (`Sfilterfunctions`, STREAMX) takes its callbacks from an `AbstractSfilter` in `filter`, and
# `Sset_filter` links a filter to the stream it filters (`upstream`, `downstream`); `Snullfunctions` is pl-file.c's null
# stream (lane D). NOT PORTED: locks and threads,
# timeouts, `tee`, the EINTR and timeout call sites of `Sset_exception` (the kernel has no signals; ENC_ANSI is the
# process's LC_CTYPE through libc: ENC1; so are ENC_UTF16BE/LE and ENC_WCHAR), close hooks (pl-file.c's `freeStream`, the one
# hook upstream registers, is called by the kernel's closers instead: src/os/pl-file.jl), `Sfprintf`
# and the other formatted output. Since R2's S1: the stream's `context` (an index into the
# database's table of the streams Prolog knows, 0: none) and `erased` (closed while a reference is
# held), reference counting (`Sacquire`, `Srelease`), `Sopen_file`, the BOM (`ScheckBOM`,
# `SwriteBOM`), `Ssize` and the seek family. Since STREAM-API: the string calls `Sfgets`, `Sfputs` and `Sfree`.

# PORT: SWI-Stream.h EOF
"End of file, as the character functions return it (SWI-Stream.h)."
const EOF = -1
# PORT: SWI-Stream.h SIO_BUFSIZE
"The default buffer size (SWI-Stream.h)."
const SIO_BUFSIZE = 4096
# PORT: SWI-Stream.h SIO_MAGIC
"An open stream's magic number (SWI-Stream.h)."
const SIO_MAGIC = 7212677
# PORT: SWI-Stream.h SIO_CMAGIC
"A closed stream's magic number (SWI-Stream.h)."
const SIO_CMAGIC = 42
# PORT: pl-stream.c UNDO_SIZE
"The push-back area before a stream's buffer: `ROUND(PL_MB_LEN_MAX, sizeof(wchar_t))` (pl-stream.c)."
const UNDO_SIZE = 16

# PORT: pl-utf8.h PL_MB_LEN_MAX
"The size of the buffer a multibyte conversion writes (pl-utf8.h)."
const PL_MB_LEN_MAX = 16

# ORIGINAL: the room for an `mbstate_t` (8 bytes on glibc, both x86_64 and aarch64): two words, zeroed, as `memset(.., 0, sizeof)`.
"The words of a zeroed `mbstate_t`."
const MBSTATE_WORDS = 2

# ORIGINAL: libc's `wcrtomb(3)` under the process's `LC_CTYPE` (the kernel never calls `setlocale`: the embedder or CT1 does).
# DIVERGES: the bytes are the answer (`nothing` for `(size_t)-1`, an unrepresentable character); `wchar_t` is a `Cint` (Linux).
"The bytes that the wide character `c` is in the process's multibyte encoding, `nothing` when it has none; `st` is the state."
function _wcrtomb(c::Int, st::Vector{UInt64})::Union{Nothing, Vector{UInt8}}
    buf = Vector{UInt8}(undef, PL_MB_LEN_MAX)
    n = GC.@preserve buf st ccall(
        :wcrtomb, Csize_t, (Ptr{UInt8}, Cint, Ptr{UInt64}), pointer(buf), c % Cint,
        pointer(st)
    )
    n == typemax(Csize_t) && return nothing
    resize!(buf, Int(n))
    return buf
end

# ORIGINAL: libc's `mbrtowc(3)` with one byte at a time (Sgetcode) or a run (read_pending_input).
"`(rc, wc)` of `mbrtowc` on `n` bytes of `buf` from `from`: `rc` is the bytes used, `-1` (illegal) or `-2` (incomplete); `wc` the character."
function _mbrtowc(
    buf::Vector{UInt8}, from::Int, n::Int, st::Vector{UInt64}
)::Tuple{Int, Int}
    wc = Ref{Cint}(0)
    rc = GC.@preserve buf st ccall(
        :mbrtowc, Csize_t, (Ptr{Cint}, Ptr{UInt8}, Csize_t, Ptr{UInt64}),
        wc, pointer(buf, from), n, pointer(st)
    )
    rc == typemax(Csize_t) && return (-1, 0)                    # (size_t)-1
    rc == typemax(Csize_t) - 1 && return (-2, 0)                # (size_t)-2
    return (Int(rc), Int(wc[]))
end

# ORIGINAL: libc's `mbsnrtowcs(NULL, &src, n, 0, ps)` (pl-file.c's HAVE_MBSNRTOWCS arm): the characters of the first `n` bytes of `buf`,
# an incomplete sequence at the end not counted; `-1` is (size_t)-1. `st` is advanced as libc does (the caller passes a copy).
"The number of wide characters in the first `n` bytes of `buf` under the process's `LC_CTYPE`, `-1` for an illegal sequence."
function _mbsnrtowcs_count(buf::Vector{UInt8}, n::Int, st::Vector{UInt64})::Int
    src = Ref{Ptr{UInt8}}(C_NULL)
    rc = GC.@preserve buf st begin
        src[] = pointer(buf)
        ccall(
            :mbsnrtowcs, Csize_t,
            (Ptr{Cint}, Ptr{Ptr{UInt8}}, Csize_t, Csize_t, Ptr{UInt64}),
            C_NULL, src, n, 0, pointer(st)
        )
    end
    rc == typemax(Csize_t) && return -1
    return Int(rc)
end

# PORT: SWI-Stream.h SIO_FBUF
"Full buffering (SWI-Stream.h)."
const SIO_FBUF = UInt32(1) << 0
# PORT: SWI-Stream.h SIO_LBUF
"Line buffering (SWI-Stream.h)."
const SIO_LBUF = UInt32(1) << 1
# PORT: SWI-Stream.h SIO_NBUF
"No buffering (SWI-Stream.h)."
const SIO_NBUF = UInt32(1) << 2
# PORT: SWI-Stream.h SIO_FEOF
"End of file seen (SWI-Stream.h)."
const SIO_FEOF = UInt32(1) << 3
# PORT: SWI-Stream.h SIO_FERR
"An error occurred (SWI-Stream.h)."
const SIO_FERR = UInt32(1) << 4
# PORT: SWI-Stream.h SIO_USERBUF
"The buffer is the user's (SWI-Stream.h)."
const SIO_USERBUF = UInt32(1) << 5
# PORT: SWI-Stream.h SIO_INPUT
"An input stream (SWI-Stream.h)."
const SIO_INPUT = UInt32(1) << 6
# PORT: SWI-Stream.h SIO_OUTPUT
"An output stream (SWI-Stream.h)."
const SIO_OUTPUT = UInt32(1) << 7
# PORT: SWI-Stream.h SIO_NOLINENO
"The line number is void (SWI-Stream.h)."
const SIO_NOLINENO = UInt32(1) << 8
# PORT: SWI-Stream.h SIO_NOLINEPOS
"The line position is void (SWI-Stream.h)."
const SIO_NOLINEPOS = UInt32(1) << 9
# PORT: SWI-Stream.h SIO_FILE
"Stream flag: refers to an OS file (SWI-Stream.h)."
const SIO_FILE = UInt32(1) << 12
# PORT: SWI-Stream.h SIO_NOCLOSE
"Stream flag: do not close on abort (SWI-Stream.h)."
const SIO_NOCLOSE = UInt32(1) << 18
# PORT: SWI-Stream.h SIO_ISATTY
"Stream flag: the stream is a tty (SWI-Stream.h)."
const SIO_ISATTY = UInt32(1) << 21

# PORT: SWI-Stream.h SIO_STATIC
"The stream is in static memory (SWI-Stream.h)."
const SIO_STATIC = UInt32(1) << 10
# PORT: SWI-Stream.h SIO_RECORDPOS
"Maintain the position (SWI-Stream.h)."
const SIO_RECORDPOS = UInt32(1) << 11
# PORT: SWI-Stream.h SIO_NOERROR
"Ignore write errors (SWI-Stream.h): the stream property `write_errors(ignore)`."
const SIO_NOERROR = UInt32(1) << 13
# PORT: SWI-Stream.h SIO_NOFEOF
"Do not set `SIO_FEOF` (SWI-Stream.h)."
const SIO_NOFEOF = UInt32(1) << 14
# PORT: SWI-Stream.h SIO_TEXT
"Text-mode operation (SWI-Stream.h)."
const SIO_TEXT = UInt32(1) << 15
# PORT: SWI-Stream.h SIO_APPEND
"Opened in append mode (SWI-Stream.h)."
const SIO_APPEND = UInt32(1) << 19
# PORT: SWI-Stream.h SIO_UPDATE
"Opened in update mode (SWI-Stream.h)."
const SIO_UPDATE = UInt32(1) << 20
# PORT: SWI-Stream.h SIO_BOM
"A BOM was detected or written (SWI-Stream.h)."
const SIO_BOM = UInt32(1) << 30
# PORT: pl-stream.c SIO_STDIO
"The flags every standard stream has (pl-stream.c)."
const SIO_STDIO = SIO_FILE | SIO_STATIC | SIO_NOCLOSE | SIO_ISATTY | SIO_TEXT
# PORT: SWI-Stream.h SIO_FEOF2
"An attempt to read past the end of file (SWI-Stream.h)."
const SIO_FEOF2 = UInt32(1) << 16
# PORT: SWI-Stream.h SIO_FEOF2ERR
"Reading past the end of file is an error (`Sfpasteof`) (SWI-Stream.h)."
const SIO_FEOF2ERR = UInt32(1) << 17
# PORT: SWI-Stream.h SIO_CLOSING
"The stream is being closed (SWI-Stream.h)."
const SIO_CLOSING = UInt32(1) << 22
# PORT: SWI-Stream.h SIO_TIMEOUT
"A timeout occurred (SWI-Stream.h)."
const SIO_TIMEOUT = UInt32(1) << 23
# PORT: SWI-Stream.h SIO_NOMUTEX
"No multi-threaded access (SWI-Stream.h)."
const SIO_NOMUTEX = UInt32(1) << 24
# PORT: SWI-Stream.h SIO_WARN
"A warning is pending (SWI-Stream.h)."
const SIO_WARN = UInt32(1) << 26
# PORT: SWI-Stream.h SIO_RAW
"A terminal stream is in raw mode (SWI-Stream.h)."
const SIO_RAW = UInt32(1) << 27
# PORT: SWI-Stream.h SIO_REPXML
"An unrepresentable character is written as an XML entity (SWI-Stream.h)."
const SIO_REPXML = UInt32(1) << 28
# PORT: SWI-Stream.h SIO_REPPL
"An unrepresentable character is written as `\\x<hex>\\` (SWI-Stream.h)."
const SIO_REPPL = UInt32(1) << 29
# PORT: SWI-Stream.h SIO_REPPLU
"An unrepresentable character is written as `\\uXXXX` (SWI-Stream.h)."
const SIO_REPPLU = UInt32(1) << 31

# PORT: SWI-Stream.h SIO_NL_POSIX
"Newlines as `\\n` (SWI-Stream.h)."
const SIO_NL_POSIX = 0
# PORT: SWI-Stream.h SIO_NL_DOS
"Newlines as `\\r\\n` (SWI-Stream.h)."
const SIO_NL_DOS = 1
# PORT: SWI-Stream.h SIO_NL_DETECT
"Detect the newline mode (SWI-Stream.h)."
const SIO_NL_DETECT = 3

# PORT: SWI-Stream.h SIO_SEEK_SET
"Seek from the start (SWI-Stream.h)."
const SIO_SEEK_SET = 0
# PORT: SWI-Stream.h SIO_SEEK_CUR
"Seek from the current position (SWI-Stream.h)."
const SIO_SEEK_CUR = 1
# PORT: SWI-Stream.h SIO_SEEK_END
"Seek from the end (SWI-Stream.h)."
const SIO_SEEK_END = 2

# PORT: SWI-Stream.h SIO_GETSIZE
"`control` action: get the size of the underlying object; `arg` is a `Ref{Int64}` (SWI-Stream.h)."
const SIO_GETSIZE = 1
# PORT: SWI-Stream.h SIO_GETFILENO
"`control` action: get the underlying file (if any); `arg` is a `Ref{Int}` (SWI-Stream.h)."
const SIO_GETFILENO = 2
# PORT: SWI-Stream.h SIO_SETENCODING
"`control` action: modify the encoding of the stream; `arg` is a `Ref{IOENC}` holding the new one (SWI-Stream.h)."
const SIO_SETENCODING = 3
# PORT: SWI-Stream.h SIO_FLUSHOUTPUT
"`control` action: flush the output (SWI-Stream.h)."
const SIO_FLUSHOUTPUT = 4
# PORT: SWI-Stream.h SIO_LASTERROR
"`control` action: the string holding the last error; `arg` is a `Ref{Union{Nothing, String}}` (SWI-Stream.h)."
const SIO_LASTERROR = 5
# PORT: SWI-Stream.h SIO_GETPENDING
"`control` action: get the number of pending bytes; `arg` is a `Ref{Int}` (SWI-Stream.h)."
const SIO_GETPENDING = 7
# PORT: SWI-Stream.h SIO_GETREPOSITION
"`control` action: test if the stream is repositionable (SWI-Stream.h)."
const SIO_GETREPOSITION = 8

# ORIGINAL: what `S_control` answers for a function set that has no `control` function (upstream's NULL pointer, which
# every caller tests: `if (s->functions->control)`): a value no real control function returns.
"The answer of `S_control` for a stream whose function set has no `control` function."
const SCONTROL_NONE = Int(typemin(Int32))

# PORT: SWI-Stream.h IOENC
"A stream's character encoding (SWI-Stream.h)."
@enum IOENC::UInt8 begin
    ENC_UNKNOWN = 0
    ENC_OCTET
    ENC_ASCII
    ENC_ISO_LATIN_1
    ENC_ANSI
    ENC_UTF8
    ENC_UTF16BE
    ENC_UTF16LE
    ENC_WCHAR
end

# PORT: SWI-Stream.h Sunicode_atoms_t
"A stream's policy for unquoted atoms with non-ASCII text (SWI-Stream.h)."
@enum Sunicode_atoms_t::UInt8 begin
    S_UATOMS_ACCEPT = 0
    S_UATOMS_NFC
    S_UATOMS_ERROR
    S_UATOMS_REJECT
end

# PORT: SWI-Stream.h io_position as IOPOS
# DIVERGES: no `reserved` field.
"A stream's position: byte, character, line and display column (SWI-Stream.h `IOPOS`)."
mutable struct IOPOS
    byteno::Int64           # byte-position in file
    charno::Int64           # character position in file
    lineno::Int             # lineno in file
    linepos::Int            # position in line
    esc_state::Int          # ANSI escape sequence state
end
IOPOS() = IOPOS(0, 0, 0, 0, 0)

# PORT: SWI-Stream.h io_functions as IOFUNCTIONS
# DIVERGES: the function set's name, where upstream holds its function pointers; `S_read`,
# `S_write`, `S_close`, `S_seek64` (lane D) and `S_control` dispatch on it.
"Which function set a stream reads, writes, seeks and closes with (SWI-Stream.h `IOFUNCTIONS`)."
@enum IOFUNCTIONS::UInt8 begin
    Smemfunctions
    Sstringfunctions
    Siofunctions
    Sstderrfunctions       # pl-file.c's: write to the stream it copies and flush it (R2 TOP1b F)
    Sfilterfunctions       # the functions an `AbstractSfilter` supplies (filter streams: zlib, hash, prolog streams; STREAMX)
    Snullfunctions         # pl-file.c's `nullFunctions` (open_null_stream/1): write is a no-op, read is at the end (lane D)
end

# PORT: pl-stream.c memfile
# DIVERGES: `buffer` is a byte vector (`nothing` for NULL), `bufferp` and `sizep` references the
# caller passed, where upstream holds pointers to the caller's variables.
"A memory file's state (pl-stream.c `memfile`)."
mutable struct memfile
    here::Int                                          # `here' location
    size::Int                                          # size of buffer
    sizep::Union{Nothing, Base.RefValue{Int}}          # pointer to size
    allocated::Int                                     # allocated size
    buffer::Union{Nothing, Vector{UInt8}}              # allocated buffer
    bufferp::Base.RefValue{Union{Nothing, Vector{UInt8}}}  # Write-back location
    malloced::Bool                                     # malloc() maintained
    free_on_close::Bool                                # free allocated buffer on close
end

# ORIGINAL: the handle of `Siofunctions` — a Julia IO in place of the OS file descriptor: a file or
# a buffer, and since R1e's write/1 family a terminal or a pipe, what a process's stdin, stdout and
# stderr are (four concrete types: a call on the field splits, no dynamic dispatch).
"A Julia IO that a stream reads from or writes to (the handle of `Siofunctions`)."
mutable struct Sjulia_io
    io::Union{IOStream, IOBuffer, Base.TTY, Base.PipeEndpoint}
    close_io::Bool                                     # close the IO with the stream
    proc::Union{Nothing, Base.Process}                 # the child of `Sopen_pipe` (`popen`), waited for at close (`pclose`)
end
Sjulia_io(io::Union{IOStream, IOBuffer, Base.TTY, Base.PipeEndpoint}, close_io::Bool) =
    Sjulia_io(io, close_io, nothing)

# ORIGINAL (STREAMX): upstream's `io_functions` (SWI-Stream.h:181-188: six C function pointers that take the stream's `handle`) is
# open: the C packages (zlib4pl.c, hash_stream.c, prolog_stream.c) each bring their own. The kernel's sets are the closed enum
# `IOFUNCTIONS` and the record in `handle`; the open set is `Sfilterfunctions`, whose record is an `AbstractSfilter` that the stream
# holds in `IOSTREAM.filter` (a `Base.RefValue{AbstractSfilter}`, a concrete type: `field_type_ok`, test/static_analysis_gates.jl:131,
# allows a Union of at most four concrete types and `handle` already has four). An implementation defines the methods below on its own
# type, as a package defines its `IOFUNCTIONS`; a method it does not define is the NULL pointer. DIVERGES: the callbacks take the
# array and the index (`mem`, `from`) where C takes a `char *`; `control`'s `arg` is a typed `Ref`, never a `void *`.
"The record of a stream over the functions `Sfilterfunctions`: a filter (zlib, hash) or a stream the caller supplies the functions of."
abstract type AbstractSfilter end

# PORT: SWI-Stream.h Sread_function (the default: a filter without a read function is never read)
"Read up to `size` bytes into `mem` at `from`: the count, 0 at end of file, -1 on error. Default -1."
Sfilter_read(::AbstractSfilter, ::Vector{UInt8}, ::Int, ::Int)::Int = -1

# PORT: SWI-Stream.h Swrite_function (the default: a filter without a write function is never written)
"Write the `size` bytes of `mem` from `from`: the count, -1 on error. Default -1."
Sfilter_write(::AbstractSfilter, ::Vector{UInt8}, ::Int, ::Int)::Int = -1

# PORT: SWI-Stream.h Sclose_function (the default: a NULL `close` closes nothing, as `S_close_wrapped` of `Sstderrfunctions`)
"Close the filter's context: 0, or -1 on error. Default 0."
Sfilter_close(::AbstractSfilter)::Int = 0

# PORT: SWI-Stream.h Scontrol_function (the default: a NULL `control`)
"Control the filter (`op` is one of the `SIO_*` actions): 0 if handled, -1 if not; `SCONTROL_NONE` (the default) is a NULL `control`."
Sfilter_control(::AbstractSfilter, ::Int, ::Any)::Int = SCONTROL_NONE

# ORIGINAL (R2 TOP1b E): the thread-local `LD` of upstream (pl-global.h `LD`/`GLOBAL_LD`) is found by thread; the kernel has
# one thread and `PL_local_data{T}` is defined AFTER this file (it holds `IOSTREAM`s), so a stream names its local
# data by a number into a table the database owns (`PL_global_data.ld_table`), the abstract supertype being all this file
# can say of it. DIVERGES (owner TH1: the table goes when threads land, the lookup is then upstream's `LD`).
"The supertype of `PL_local_data{T}` (src/pl-global.jl): the type a stream's registered local data is held under."
abstract type AbstractLocalData end

"The table of registered local data (`PL_global_data.ld_table`): an entry is a wrapped stream's engine, `nothing` once free."
const LDTable = Vector{Union{Nothing, AbstractLocalData}}

# ORIGINAL: the kernel's counterpart of upstream's `GET_LD` (the thread's `LD` is found by number, see the comment above).
"Register `ld` in the table `tbl` (the first free entry, else a new one): its number."
function registerLocalData!(tbl::LDTable, ld::AbstractLocalData)::Int
    i = findfirst(isnothing, tbl)
    if i === nothing
        push!(tbl, ld)
        return length(tbl)
    end
    tbl[i] = ld
    return i
end

"Free the entry `i` of the table `tbl` (the stream that held it was closed)."
function unregisterLocalData!(tbl::LDTable, i::Int)::Nothing
    1 <= i <= length(tbl) && (tbl[i] = nothing)
    return nothing
end

# PORT: pl-file.c wrappedIO
# (swipl-devel cbf4e189, src/os/pl-file.c:5970-5977)
# DIVERGES: the wrapped stream keeps its own `handle` and `functions` (upstream replaces both with the record and a
# function block that holds the originals): the record is `IOSTREAM.wrapped`, the originals stay where they were, so
# nothing that reads `handle` or `functions` (`file_name`, `Ssize`, `isStringStream`) changes. `functions` is not a
# function block but `user_read`: whether the replacement of `read` is `Sread_user` (the one use, set_prolog_IO/3; the
# `write` replacement is never given). `wrapped_stream` is the stream whose `wrapped` this is (S_read and S_close
# have it). `ld` is the number of the registered local data (see `AbstractLocalData`), `table` the database's.
"What `wrapIO` records about a stream it wrapped (pl-file.c `wrappedIO`)."
mutable struct wrappedIO
    table::LDTable                      # PL_global_data.ld_table: where `ld` is looked up
    ld::Int                             # the registered local data of the engine the read prompts for
    user_read::Bool                     # functions.read == Sread_user
    saved_flags::UInt32                 # SIO_flags we must restore
end

# The stream layer's view of pl-locale.h `PL_locale` (`IOSTREAM.locale` is a `PL_locale *`): an abstract supertype only: the locale object `PL_locale_rec{T}` (src/pl-global.jl) is parametric in the
# term type and defined after this file; the stream holds the object itself (so `update_locale`'s change of the system
# default shows in every stream that holds it, as upstream). `acquireLocale` and `releaseLocale` (pl-locale.c) are defined
# HERE, on the abstract type, through `getfield`/`setfield!` of the fields `references`, `symbol`, `alias`, so that the
# call from a stream (whose `locale` field has the abstract type) is one method and not a run-time dispatch; every locale
# object, whatever its term type, is counted by them (src/os/pl-locale.jl calls them).
"A locale object as the stream layer holds it (`IOSTREAM.locale`, pl-locale.h `PL_locale *`)."
abstract type IOLocale end

# PORT: pl-locale.c acquireLocale
"Count a new reference to `l` (pl-locale.c)."
function acquireLocale(l::L)::L where {L <: IOLocale}
    setfield!(l, :references, (getfield(l, :references)::Int) + 1)
    return l
end

# PORT: pl-locale.c releaseLocale
# (free_locale: the strings, the alias and the magic of the object are cleared, as src/os/pl-locale.jl `free_locale`)
"Drop a reference to `l`; free it when nothing names it any more (pl-locale.c)."
function releaseLocale(l::IOLocale)::Nothing
    n = getfield(l, :references)::Int
    @assert n > 0
    setfield!(l, :references, n - 1)
    if n == 1 && getfield(l, :symbol) === nothing && getfield(l, :alias) === nothing
        setfield!(l, :decimal_point, "")
        setfield!(l, :thousands_sep, "")
        setfield!(l, :grouping, Int[0])
        setfield!(l, :magic, 0)
    end
    return nothing
end

# PORT: pl-stream.c the `record_t exception` of an IOSTREAM
# DIVERGES: `record_t` is `record{T}` (src/pl-incl.jl), defined after this file and parametrised by the term type: the stream holds
# it behind this supertype, and `StreamException{T}` (src/os/pl-file.jl, the one subtype) wraps the record.
"The pending exception of a stream (`IOSTREAM.exception`): upstream's `record_t`, whose one subtype is `StreamException{T}` (src/os/pl-file.jl)."
abstract type AbstractStreamException end

# PORT: SWI-Stream.h io_stream as IOSTREAM
# DIVERGES: see the file's header — the buffer pointers are indices into `mem`, `functions` names a
# function set (`filter` holds the callbacks of `Sfilterfunctions`, where upstream's `functions` and `handle` are
# the pointer table and the context); the fields of the parts not ported are absent (`timeout`, `tee`). `context` is upstream's `void
# *context` (pl-file.c's `stream_context`): an index into the database's stream table
# (`PL_global_data.stream_table`) instead of a pointer to a record, 0 for NULL.
"A stream (SWI-Stream.h `IOSTREAM`)."
mutable struct IOSTREAM
    mem::Vector{UInt8}                  # the memory `buffer`, `unbuffer`, `bufp`, `limitp` index
    bufp::Int                           # `here'
    limitp::Int                         # read/write limit
    buffer::Int                         # the buffer (0: none)
    unbuffer::Int                       # Sungetc buffer
    lastc::Int                          # last character written
    magic::Int                          # magic number SIO_MAGIC
    bufsize::Int                        # size of the buffer
    flags::UInt32                       # Status flags
    posbuf::IOPOS                       # location in file
    position::Union{Nothing, IOPOS}     # pointer to above
    handle::Union{Nothing, memfile, IOSTREAM, Sjulia_io}  # function's handle
    functions::IOFUNCTIONS              # open/close/read/write/seek
    encoding::IOENC                     # character encoding used
    references::Int                     # Reference-count
    newline::Int                        # Newline mode
    io_errno::Int                       # Save errno value
    message::Union{Nothing, String}     # error/warning message
    unicode_atoms::Sunicode_atoms_t     # per-stream atom-content policy
    context::Int                        # the stream's entry in the database's stream table (0: none)
    erased::Bool                        # closed while a reference is held
    wrapped::Union{Nothing, wrappedIO}  # what wrapIO() replaced the read of (pl-file.c: `handle` is the wrappedIO)
    locale::Union{Nothing, IOLocale}    # the locale (`fd->locale`): numbers `~:d` and `~:f` print by (nothing: NULL)
    upstream::Union{Nothing, IOSTREAM}  # stream providing our input (the filter on this stream; SWI-Stream.h)
    downstream::Union{Nothing, IOSTREAM}  # stream providing our output (the stream this filter filters)
    filter::Union{Nothing, Base.RefValue{AbstractSfilter}}  # the functions and context of a `Sfilterfunctions` stream
    fileno::Int                         # the cached file number (`Sfileno`), -1: none
    exception::Union{Nothing, Base.RefValue{AbstractStreamException}}  # the recorded exception (`Sset_exception`)
    mbstate::Union{Nothing, Vector{UInt64}}  # ENC_ANSI decoding: the `mbstate_t` (nothing: NULL; see `stream_mbstate!`)
    IOSTREAM() = new(
        UInt8[], 0, 0, 0, 0, EOF, 0, 0, UInt32(0), IOPOS(), nothing, nothing,
        Smemfunctions,
        ENC_UNKNOWN, 0, SIO_NL_POSIX, 0, nothing, S_UATOMS_ACCEPT, 0, false, nothing,
        nothing, nothing, nothing, nothing, -1, nothing, nothing
    )
end

# ORIGINAL: pl-stream.c's `if ( !s->mbstate ) { malloc; memset 0 }` of put_code and Sgetcode (and pl-file.c's read_pending_input)
# DIVERGES: the state is a `Vector{UInt64}`, collected by the GC (upstream frees it in Sclose_ and at shutdown, `free(s->mbstate)`).
"The `mbstate_t` of `s`: made zeroed the first time (pl-stream.c)."
function stream_mbstate!(s::IOSTREAM)::Vector{UInt64}
    st = s.mbstate
    if st === nothing
        st = zeros(UInt64, MBSTATE_WORDS)
        s.mbstate = st
    end
    return st
end

# ── the function sets ───────────────────────────────────────────────────────────────────────────
# What upstream's `(*s->functions->read)(s->handle, buf, size)` and the other calls through the
# table do: the function of the stream's set, on its handle. `from` is an index into `mem`.

"Read up to `size` bytes into `mem` at `from`: the count, 0 at end of file, -1 on error."
function S_read(s::IOSTREAM, mem::Vector{UInt8}, from::Int, size::Int)::Int
    w = s.wrapped
    if w !== nothing && w.user_read
        return Sread_user(w.table[w.ld], s, w, mem, from, size)::Int   # (the barrier: src/os/pl-file.jl `Sread_user`)
    end
    return S_read_wrapped(s, mem, from, size)
end

"Read as the stream's own function set does, the one a wrapper (pl-file.c `wrapIO`) calls as `wrapped_functions->read`."
function S_read_wrapped(s::IOSTREAM, mem::Vector{UInt8}, from::Int, size::Int)::Int
    h = s.handle
    s.functions == Smemfunctions && h isa memfile &&
        return Sread_memfile(h, mem, from, size)
    s.functions == Siofunctions && h isa Sjulia_io &&
        return Sread_julia_io(h, mem, from, size)
    s.functions == Sfilterfunctions && return Sread_filter(s, mem, from, size)
    s.functions == Snullfunctions && return Sread_null(mem, from, size)
    return Sread_string(s, mem, from, size)
end

"Write the `size` bytes of `mem` from `from`: the count, -1 on error."
function S_write(s::IOSTREAM, mem::Vector{UInt8}, from::Int, size::Int)::Int
    h = s.handle
    s.functions == Smemfunctions && h isa memfile &&
        return Swrite_memfile(h, mem, from, size)
    s.functions == Siofunctions && h isa Sjulia_io &&
        return Swrite_julia_io(h, mem, from, size)
    s.functions == Sstderrfunctions && h isa IOSTREAM &&
        return Swrite_stderr(h, mem, from, size)
    s.functions == Sfilterfunctions && return Swrite_filter(s, mem, from, size)
    s.functions == Snullfunctions && return Swrite_null(mem, from, size)
    return Swrite_string(s, mem, from, size)
end

"Close the stream's handle: 0, or -1 on error."
function S_close(s::IOSTREAM)::Int
    w = s.wrapped
    w === nothing || return closeWrappedIO(s, w)
    return S_close_wrapped(s)
end

"Close as the stream's own function set does, the one a wrapper (pl-file.c `closeWrappedIO`) calls as `wrapped_functions->close`."
function S_close_wrapped(s::IOSTREAM)::Int
    h = s.handle
    s.functions == Smemfunctions && h isa memfile && return Sclose_memfile(h)
    s.functions == Siofunctions && h isa Sjulia_io && return Sclose_julia_io(h)
    s.functions == Sstderrfunctions && return 0                 # (`close` is NULL)
    s.functions == Sfilterfunctions && return Sclose_filter(s)
    s.functions == Snullfunctions && return Sclose_null()
    h isa IOSTREAM && return Sclose_string(h)
    return -1
end

# ORIGINAL (STREAMX): the three barrier functions below are where the open set's indirect call is, the kernel's counterpart of
# `(*s->functions->read)(s->handle, ...)`; the call is one runtime dispatch on the `AbstractSfilter` in `s.filter` (the JET
# gate's `JET_DISPATCH_ALLOWED`, test/static_analysis_manifest.jl).
"Read through the filter functions of `s` (`Sfilterfunctions`): the count, 0 at end of file, -1 on error."
function Sread_filter(s::IOSTREAM, mem::Vector{UInt8}, from::Int, size::Int)::Int
    f = s.filter
    f === nothing && return -1
    return Sfilter_read(f[], mem, from, size)::Int
end

"Write through the filter functions of `s` (`Sfilterfunctions`): the count, -1 on error."
function Swrite_filter(s::IOSTREAM, mem::Vector{UInt8}, from::Int, size::Int)::Int
    f = s.filter
    f === nothing && return -1
    return Sfilter_write(f[], mem, from, size)::Int
end

"Close the filter functions of `s` (`Sfilterfunctions`): 0, or -1 on error."
function Sclose_filter(s::IOSTREAM)::Int
    f = s.filter
    f === nothing && return 0
    return Sfilter_close(f[])::Int
end

# PORT: SWI-Stream.h Scontrol_function as S_control
# DIVERGES: upstream tests the function pointer at each call (`if (s->functions->control)`) and calls it with `s->handle`;
# here one function does both: `SCONTROL_NONE` says there is no control function (every set but a filter that defines one).
"Call the control function of `s`'s function set with `op` (an `SIO_*` action) and `arg`: its result, or `SCONTROL_NONE`."
function S_control(s::IOSTREAM, op::Int, @nospecialize(arg))::Int
    if s.functions == Sfilterfunctions
        f = s.filter
        f === nothing || return Sfilter_control(f[], op, arg)::Int
    end
    return SCONTROL_NONE
end

# ── buffers ─────────────────────────────────────────────────────────────────────────────────────

# PORT: pl-stream.c S__setbuf
# DIVERGES: `buffer` is the user's byte vector (`nothing`: allocate one), the indices of the new
# buffer follow from it.
"Give `s` a buffer of `size` bytes (0: `SIO_BUFSIZE`): the user's `buffer`, or a new one (pl-stream.c)."
function S__setbuf(s::IOSTREAM, buffer::Union{Nothing, Vector{UInt8}}, size::Int)::Int
    newflags = s.flags
    size == 0 && (size = SIO_BUFSIZE)
    if (s.flags & SIO_OUTPUT) != 0
        S__removebuf(s) < 0 && return -1
    end
    if buffer !== nothing
        newmem = buffer
        newunbuf = newbuf = 1
        newflags |= SIO_USERBUF
    else
        newmem = Vector{UInt8}(undef, size + UNDO_SIZE)
        newflags &= ~SIO_USERBUF
        newunbuf = 1
        newbuf = newunbuf + UNDO_SIZE
    end
    if (s.flags & SIO_INPUT) != 0
        buffered = s.limitp - s.bufp
        copy = buffered < size ? buffered : size
        # upstream seeks back over what does not fit (`size < buffered`); a buffer is only ever
        # set here on a stream that has none, so nothing is buffered
        @assert size >= buffered
        copy > 0 && copyto!(newmem, newbuf, s.mem, s.bufp, copy)
        S__removebuf(s)
        s.mem = newmem
        s.unbuffer = newunbuf
        s.bufp = s.buffer = newbuf
        s.limitp = s.buffer + copy
    else
        s.mem = newmem
        s.unbuffer = newunbuf
        s.bufp = s.buffer = newbuf
        s.limitp = s.buffer + size
    end
    s.bufsize = size
    s.flags = newflags
    return size
end

# PORT: pl-stream.c Ssetbuffer
"Give `s` a buffer of `size` bytes; a user buffer loses its `SIO_USERBUF` mark (pl-stream.c)."
function Ssetbuffer(s::IOSTREAM, buffer::Union{Nothing, Vector{UInt8}}, size::Int)::Nothing
    S__setbuf(s, buffer, size) != -1 && (s.flags &= ~SIO_USERBUF)
    return nothing
end

# PORT: pl-stream.c Ssetenc
# DIVERGES: only a filter's function set has a `control` function (SIO_SETENCODING, `S_control`) and the old encoding is
# not returned (`old` is NULL at the one caller).
"Set the encoding of `s`; ENC_OCTET clears SIO_TEXT, any other sets it; 0 (pl-stream.c)."
function Ssetenc(s::IOSTREAM, enc::IOENC)::Int
    enc == s.encoding && return 0
    if s.functions == Sfilterfunctions
        rc = S_control(s, SIO_SETENCODING, Ref(enc))
        rc != SCONTROL_NONE && rc != 0 && return -1
    end
    s.encoding = enc
    if enc == ENC_OCTET
        s.flags &= ~SIO_TEXT
    else
        s.flags |= SIO_TEXT
    end
    return 0
end

# PORT: pl-stream.c S__removebuf
"Drop `s`'s buffer, flushing an output stream's first (pl-stream.c)."
function S__removebuf(s::IOSTREAM)::Int
    if s.buffer != 0 && s.unbuffer != 0
        rval = 0
        (s.flags & SIO_OUTPUT) != 0 && S__flushbuf(s) < 0 && (rval = -1)
        s.bufp = s.limitp = s.buffer = s.unbuffer = 0
        (s.flags & SIO_USERBUF) == 0 && (s.mem = UInt8[])   # free(s->unbuffer)
        s.bufsize = 0
        return rval
    end
    return 0
end

# PORT: pl-stream.c S__flushbuf
"Write out `s`'s buffer: the bytes written, or -1 on error (pl-stream.c)."
function S__flushbuf(s::IOSTREAM)::Int
    s.magic != SIO_MAGIC && return -1
    from = s.buffer
    to = s.bufp
    while from < to
        size = to - from
        n = S_write(s, s.mem, from, size)
        if n > 0                            # wrote some
            from += n
        elseif n < 0                        # error
            S__seterror(s)
            return -1
        else                                # wrote nothing?
            break
        end
    end
    if to == from                           # full flush
        rc = s.bufp - s.buffer
        s.bufp = s.buffer
    else                                    # partial flush
        left = to - from
        rc = from - s.buffer
        copyto!(s.mem, s.buffer, s.mem, from, left)
        s.bufp = s.buffer + left
    end
    return rc
end

# PORT: pl-stream.c S__flushbufc
"Flush `s`'s full buffer and add byte `c`: `c`, or -1 on error (pl-stream.c)."
function S__flushbufc(c::Int, s::IOSTREAM)::Int
    if s.buffer != 0
        if S__flushbuf(s) <= 0              # == 0: no progress!?
            c = -1
        else
            s.mem[s.bufp] = c % UInt8
            s.bufp += 1
        end
    else
        if (s.flags & SIO_NBUF) != 0
            one = UInt8[c % UInt8]
            if S_write(s, one, 1, 1) != 1
                S__seterror(s)
                c = -1
            end
        else
            if S__setbuf(s, nothing, 0) == -1
                c = -1
            else
                s.mem[s.bufp] = c % UInt8
                s.bufp += 1
            end
        end
    end
    return c
end

# PORT: pl-stream.c S__fillbuf
# DIVERGES: no timeouts (`S__wait`), no signal handling on EINTR.
"Refill `s`'s buffer and return its first byte, or -1 at end of file or on error (pl-stream.c)."
function S__fillbuf(s::IOSTREAM)::Int
    s.magic != SIO_MAGIC && return -1
    if (s.flags & (SIO_FEOF | SIO_FERR)) != 0          # reading past eof
        if (s.flags & SIO_FEOF2ERR) != 0
            Sseterr(s, SIO_FEOF2 | SIO_FERR, nothing)
        else
            s.flags |= SIO_FEOF2
        end
        return -1
    end
    if (s.flags & SIO_NBUF) != 0
        chr = UInt8[0x00]
        n = S_read(s, chr, 1, 1)
        if n == 1
            return Int(chr[1])
        elseif n == 0
            (s.flags & SIO_NOFEOF) == 0 && (s.flags |= SIO_FEOF)
            return -1
        else
            S__seterror(s)
            return -1
        end
    else
        if s.buffer == 0
            S__setbuf(s, nothing, 0) == -1 && return -1
            s.bufp = s.limitp = s.buffer
            len = s.bufsize
        elseif s.bufp < s.limitp
            len = s.limitp - s.bufp
            if len == s.bufsize
                c = Int(s.mem[s.bufp])
                s.bufp += 1
                return c
            end
            copyto!(s.mem, s.buffer, s.mem, s.bufp, s.limitp - s.bufp)
            s.bufp = s.buffer
            s.limitp = s.bufp + len
            len = s.bufsize - len
        else
            s.bufp = s.limitp = s.buffer
            len = s.bufsize
        end
        n = S_read(s, s.mem, s.limitp, len)
        if n > 0
            s.limitp += n
            c = Int(s.mem[s.bufp])
            s.bufp += 1
            return c
        elseif n == 0
            (s.flags & SIO_NOFEOF) == 0 && (s.flags |= SIO_FEOF)
            return -1
        else
            Sferror(s) != 0 && return -1
            S__seterror(s)
            return -1
        end
    end
end

# PORT: SWI-Stream.h Snpgetc
"The next byte of `s`, without updating the position (SWI-Stream.h)."
@inline function Snpgetc(s::IOSTREAM)::Int
    if s.bufp < s.limitp
        c = Int(s.mem[s.bufp])
        s.bufp += 1
        return c
    end
    return S__fillbuf(s)
end

# ── positions ───────────────────────────────────────────────────────────────────────────────────

# PORT: pl-stream.c ANSI_ESC
"The escape character (pl-stream.c)."
const ANSI_ESC = Int(0x1b)
# PORT: pl-stream.c ANSI_BEL
"The bell character (pl-stream.c)."
const ANSI_BEL = Int(0x07)
# PORT: pl-stream.c IOPOS_ESC_NONE
"Not in an escape sequence (pl-stream.c)."
const IOPOS_ESC_NONE = 0
# PORT: pl-stream.c IOPOS_ESC_ESC
"Seen ESC (pl-stream.c)."
const IOPOS_ESC_ESC = 1
# PORT: pl-stream.c IOPOS_ESC_CSI
"Seen ESC [ (pl-stream.c)."
const IOPOS_ESC_CSI = 2
# PORT: pl-stream.c IOPOS_ESC_OSC
"Seen ESC ] (pl-stream.c)."
const IOPOS_ESC_OSC = 3
# PORT: pl-stream.c IOPOS_ESC_OSC_ESC
"Seen ESC inside OSC (pl-stream.c)."
const IOPOS_ESC_OSC_ESC = 4
# PORT: pl-stream.c IOPOS_ESC_SHIFT
"The escape state's bits (pl-stream.c)."
const IOPOS_ESC_SHIFT = 3
# PORT: pl-stream.c IOPOS_ESC_MASK
"The escape state's mask (pl-stream.c)."
const IOPOS_ESC_MASK = (1 << IOPOS_ESC_SHIFT) - 1
# PORT: pl-stream.c IOPOS_ESC_MAX
"The longest escape sequence followed (pl-stream.c)."
const IOPOS_ESC_MAX = 256

# PORT: pl-stream.c Supdateesc
"Follow `c` through an ANSI escape sequence: true if it belongs to one (pl-stream.c)."
function Supdateesc(p::IOPOS, c::Int)::Bool
    state = p.esc_state & IOPOS_ESC_MASK
    if state == IOPOS_ESC_NONE
        c != ANSI_ESC && return false
        p.esc_state = IOPOS_ESC_ESC | (1 << IOPOS_ESC_SHIFT)
        return true
    end
    len = p.esc_state >> IOPOS_ESC_SHIFT
    abort = len >= IOPOS_ESC_MAX
    if !abort
        if state == IOPOS_ESC_ESC
            if c == Int('[')
                state = IOPOS_ESC_CSI
            elseif c == Int(']')
                state = IOPOS_ESC_OSC
            elseif c >= 0x20 && c <= 0x2f
                # intermediate byte
            elseif c >= 0x20
                state = IOPOS_ESC_NONE          # final byte
            else
                abort = true
            end
        elseif state == IOPOS_ESC_CSI
            if c >= 0x20 && c <= 0x3f
                # parameter/intermediate byte
            elseif c >= 0x40 && c <= 0x7e
                state = IOPOS_ESC_NONE          # final byte
            else
                abort = true
            end
        elseif state == IOPOS_ESC_OSC
            if c == ANSI_BEL
                state = IOPOS_ESC_NONE
            elseif c == ANSI_ESC
                state = IOPOS_ESC_OSC_ESC
            elseif c < 0x20
                abort = true
            end
        elseif state == IOPOS_ESC_OSC_ESC
            if c == Int('\\')                   # ST
                state = IOPOS_ESC_NONE
            else
                abort = true
            end
        end
    end
    if abort
        p.esc_state = 0
        return Supdateesc(p, c)                 # c may start a new sequence
    end
    p.esc_state = state != 0 ? (state | ((len + 1) << IOPOS_ESC_SHIFT)) : 0
    return true
end

# PORT: pl-stream.c Supdatepos
"Advance the position over character `c`: true if the line position is reliable again (pl-stream.c)."
function Supdatepos(p::IOPOS, c::Int)::Bool
    if c >= Int(' ') && c < 0x7f && p.esc_state == 0
        p.linepos += 1                          # speedup the 99% case a bit
        return false
    end
    Supdateesc(p, c) && return false
    if c == Int('\n')
        p.lineno += 1
        p.linepos = 0
        return true
    elseif c == Int('\r')
        p.linepos = 0
        return true                             # linepos is reliable again
    elseif c == Int('\b')
        p.linepos > 0 && (p.linepos -= 1)
    elseif c == Int('\t')
        p.linepos = (p.linepos | 7) + 1         # next multiple of 8
    else
        w = PL_wcwidth(c)                       # -1 if not printable
        w > 0 && (p.linepos += w)
    end
    return false
end

# PORT: pl-stream.c Sresetesc
"Discard a partly seen escape sequence (pl-stream.c)."
Sresetesc(p::IOPOS)::Nothing = (p.esc_state=0; nothing)

# PORT: pl-stream.c update_linepos
"Advance `s`'s line position over `c` (pl-stream.c)."
function update_linepos(s::IOSTREAM, c::Int)::Nothing
    p = s.position
    p === nothing && return nothing
    Supdatepos(p, c) && (s.flags &= ~SIO_NOLINEPOS)
    return nothing
end

# PORT: pl-stream.c S__fupdatefilepos_getc
"Advance `s`'s position over byte `c` read (pl-stream.c)."
function S__fupdatefilepos_getc(s::IOSTREAM, c::Int)::Int
    p = s.position
    if c != EOF && p !== nothing
        update_linepos(s, c)
        p.byteno += 1
        p.charno += 1
    end
    return c
end

# PORT: SWI-Stream.h S__updatefilepos_getc
"Advance `s`'s position over byte `c` read, if it keeps one (SWI-Stream.h)."
@inline S__updatefilepos_getc(s::IOSTREAM, c::Int)::Int =
    s.position !== nothing ? S__fupdatefilepos_getc(s, c) : c

# PORT: pl-stream.c S__updatefilepos
"Advance `s`'s character position over `c` (pl-stream.c)."
function S__updatefilepos(s::IOSTREAM, c::Int)::Int
    p = s.position
    if p !== nothing && c != EOF
        update_linepos(s, c)
        p.charno += 1
    end
    return c
end

# PORT: SWI-Stream.h Sgetc
"The next byte of `s` (SWI-Stream.h)."
Sgetc(s::IOSTREAM)::Int = S__updatefilepos_getc(s, Snpgetc(s))

# PORT: pl-stream.c get_byte
"The next byte of `s`, counting it in the byte position (pl-stream.c)."
function get_byte(s::IOSTREAM)::Int
    c = Snpgetc(s)
    p = s.position
    p !== nothing && c != EOF && (p.byteno += 1)
    return c
end

# PORT: pl-stream.c put_byte
"Write byte `c` to `s`: `c`, or -1 on error (pl-stream.c)."
function put_byte(c::Int, s::IOSTREAM)::Int
    c &= 0xff
    if s.bufp < s.limitp
        s.mem[s.bufp] = c % UInt8
        s.bufp += 1
    else
        if S__flushbufc(c, s) < 0
            s.lastc = EOF
            return -1
        end
    end
    p = s.position
    p !== nothing && (p.byteno += 1)
    return c
end

# PORT: pl-stream.c Sputc
"Write byte `c` to `s`: `c`, or -1 on error (pl-stream.c)."
function Sputc(c::Int, s::IOSTREAM)::Int
    c &= 0xff
    put_byte(c, s) < 0 && return -1
    s.lastc = c
    if c == Int('\n') && (s.flags & SIO_LBUF) != 0
        S__flushbuf(s) < 0 && return -1
    end
    return S__updatefilepos(s, c)
end

# PORT: pl-stream.c unget_byte
"Push byte `c` back onto `s`, its position moved back (pl-stream.c)."
function unget_byte(c::Int, s::IOSTREAM)::Nothing
    p = s.position
    s.bufp -= 1
    s.mem[s.bufp] = c % UInt8
    if p !== nothing
        p.charno -= 1                           # FIXME: not correct
        p.byteno -= 1
        c == Int('\n') && (p.lineno -= 1)
        Sresetesc(p)
        s.flags |= SIO_NOLINEPOS
    end
    return nothing
end

# PORT: pl-stream.c Sungetc
"Push byte `c` back onto `s`: `c`, or -1 if there is no room (pl-stream.c)."
function Sungetc(c::Int, s::IOSTREAM)::Int
    if s.bufp > s.unbuffer
        unget_byte(c, s)
        return c
    end
    return -1
end

# PORT: pl-stream.c Sfread
# DIVERGES: `data` is a byte vector filled from index 1 (upstream's `void *`); `size` 0 reads nothing (upstream divides by it).
"Read up to `elms` elements of `size` bytes from `s` into `data`: the number of whole elements read (pl-stream.c)."
function Sfread(data::Vector{UInt8}, size::Int, elms::Int, s::IOSTREAM)::Int
    size == 0 && return 0
    chars = size * elms
    bi = 1                                      # `buf`: the next index of `data`
    if s.position !== nothing
        while chars > 0
            c = Sgetc(s)
            c == EOF && break
            data[bi] = c % UInt8
            bi += 1
            chars -= 1
        end
    else
        while chars > 0
            if s.bufp < s.limitp
                avail = s.limitp - s.bufp
                if chars <= avail
                    copyto!(data, bi, s.mem, s.bufp, chars)
                    s.bufp += chars
                    return elms
                else
                    copyto!(data, bi, s.mem, s.bufp, avail)
                    chars -= avail
                    bi += avail
                    s.bufp += avail
                end
            end
            c = S__fillbuf(s)
            c == EOF && break
            data[bi] = c % UInt8
            bi += 1
            chars -= 1
        end
    end
    return (size * elms - chars) ÷ size
end

# PORT: pl-stream.c Sfwrite
# DIVERGES: `data` is a byte vector read from index 1 (upstream's `void *`); `size` 0 writes nothing (upstream divides by it).
"Write `elms` elements of `size` bytes from `data` to `s`: the number of whole elements written (pl-stream.c)."
function Sfwrite(data::Vector{UInt8}, size::Int, elms::Int, s::IOSTREAM)::Int
    size == 0 && return 0
    chars = size * elms
    bi = 1
    while chars > 0
        Sputc(Int(data[bi]), s) < 0 && break
        bi += 1
        chars -= 1
    end
    return (size * elms - chars) ÷ size
end

# PORT: SWI-Stream.h SIO_RP_BLOCK
"`Sread_pending` flag: wait for new input if nothing is buffered (SWI-Stream.h)."
const SIO_RP_BLOCK = 1
# PORT: SWI-Stream.h SIO_RP_NOPOS
"`Sread_pending` flag: do not update the position (SWI-Stream.h)."
const SIO_RP_NOPOS = 2

# PORT: pl-stream.c Sread_pending
# DIVERGES: `buf` is a byte vector filled from index 1 (upstream's `char *`); the count is the bytes delivered, an end of file the
# stream's own (`Sfpasteof`) is 0, any other failure -1.
"Read what is buffered on `s` (at most `limit` bytes) into `buf`; with `SIO_RP_BLOCK` fill the buffer first if it is empty: the count (pl-stream.c)."
function Sread_pending(s::IOSTREAM, buf::Vector{UInt8}, limit::Int, flags::Int)::Int
    done = 0
    if s.bufp >= s.limitp && (flags & SIO_RP_BLOCK) != 0
        c = S__fillbuf(s)
        if c < 0
            (s.flags & SIO_FEOF) != 0 && Sfpasteof(s) != 1 && return 0
            return c
        end
        buf[1] = c % UInt8
        limit -= 1
        done = 1
    end
    n = s.limitp - s.bufp
    n > limit && (n = limit)
    copyto!(buf, done + 1, s.mem, s.bufp, n)
    if s.position !== nothing && (flags & SIO_RP_NOPOS) == 0
        p = s.position
        for i in 1:(done + n)
            update_linepos(s, Int(buf[i]))
            p.charno += 1
        end
    end
    s.bufp += n
    return done + n
end

# PORT: pl-stream.c Spending
# DIVERGES: the control function is a filter's (`S_control`, `SIO_GETPENDING`, a `Ref{Int}`); no other function set has one.
"The number of bytes pending on `s`: the buffered ones, else what the control function says (pl-stream.c)."
function Spending(s::IOSTREAM)::Int
    s.bufp < s.limitp && return s.limitp - s.bufp
    pending = Ref(0)
    S_control(s, SIO_GETPENDING, pending) == 0 && return pending[]
    return 0
end

# PORT: pl-stream.c S__fileno
# DIVERGES: upstream's `SIO_FILE` stream is its handle (the OS descriptor): no stream here holds one, so only a control function
# (a filter's, `SIO_GETFILENO`, a `Ref{Int}`) can answer.
"The file number `s`'s control function reports, or -1 (pl-stream.c)."
function S__fileno(s::IOSTREAM)::Int
    if s.magic == SIO_MAGIC
        n = Ref(0)
        S_control(s, SIO_GETFILENO, n) == 0 && return n[]
    end
    return -1                                   # errno = EINVAL
end

# PORT: pl-stream.c Sfileno
# DIVERGES: the cached `fileno` is set by `Snew` of a filter stream only (`S__fileno`); the standard streams' 0, 1, 2 are
# `_std_fileno`'s (src/os/pl-file.jl, FILENO1), a file stream has none.
"The cached file number of `s`: >= 0, or -1 (pl-stream.c)."
function Sfileno(s::IOSTREAM)::Int
    s.magic != SIO_MAGIC && return -1           # errno = EINVAL
    s.fileno >= 0 && return s.fileno
    return -1
end

# ── characters ──────────────────────────────────────────────────────────────────────────────────

# PORT: pl-stream.c reperror
"An unrepresentable character `c`: its escape if `s` asks for one, else an error (pl-stream.c)."
function reperror(c::Int, s::IOSTREAM)::Int
    if c >= 0 && (s.flags & (SIO_REPXML | SIO_REPPL | SIO_REPPLU)) != 0
        if (s.flags & SIO_REPPL) != 0
            buf = string("\\x", uppercase(string(c; base=16)), "\\")
        elseif (s.flags & SIO_REPPLU) != 0
            buf = if c <= 0xffff
                string("\\u", uppercase(string(c; base=16, pad=4)))
            else
                string("\\U", uppercase(string(c; base=16, pad=8)))
            end
        else
            buf = string("&#", c, ";")
        end
        for q in codeunits(buf)                 # The escape is ASCII, but we must encode it
            put_code(Int(q), s) < 0 && return -1
        end
        return c
    end
    Sseterr(s, SIO_FERR, "Encoding cannot represent character")
    return -1
end

# PORT: pl-stream.c put_usc2
"Write the 16-bit unit `c` to `s`, big endian when `be` (pl-stream.c): 0, or -1 on error."
function put_usc2(c::Int, s::IOSTREAM, be::Bool)::Int
    if be
        (put_byte(c >> 8, s) < 0 || put_byte(c & 0xff, s) < 0) && return -1
    else
        (put_byte(c & 0xff, s) < 0 || put_byte(c >> 8, s) < 0) && return -1
    end
    return 0
end

# PORT: pl-stream.c put_utf16
"Write `c` to `s` as UTF-16, a surrogate pair above 0xffff (pl-stream.c): 0, or -1 on error."
function put_utf16(c::Int, s::IOSTREAM, be::Bool)::Int
    if c > 0xffff
        c1, c2 = utf16_encode(c)
        (
            put_usc2(c1, s, s.encoding == ENC_UTF16BE) < 0 ||
            put_usc2(c2, s, s.encoding == ENC_UTF16BE) < 0
        ) && return -1
    elseif IS_UTF16_SURROGATE(c)
        reperror(c, s) < 0 && return -1
    else
        put_usc2(c, s, s.encoding == ENC_UTF16BE) < 0 && return -1
    end
    return 0
end

# PORT: pl-stream.c put_code
# DIVERGES: ENC_ANSI is libc's `wcrtomb` under the process's LC_CTYPE (the kernel never calls `setlocale`), with the stream's `mbstate`
# (`stream_mbstate!`); `ENC_WCHAR` is the 4-byte `wchar_t` of this platform (SIZEOF_WCHAR_T == 4, in the machine's byte order: `ENDIAN_BOM`;
# upstream's `#else` arm), the code truncated to 32 bits as `pl_wchar_t chr = c` does.
"Write character `c` to `s` in its encoding: `c`, or -1 on error (pl-stream.c)."
function put_code(c::Int, s::IOSTREAM)::Int
    IS_UTF16_SURROGATE(c) && return reperror(c, s)
    enc = s.encoding
    if enc == ENC_OCTET || enc == ENC_ISO_LATIN_1
        if c >= 256
            reperror(c, s) < 0 && return -1
        else
            put_byte(c, s) < 0 && return -1
        end
    elseif enc == ENC_ASCII
        if c >= 128
            reperror(c, s) < 0 && return -1
        else
            put_byte(c, s) < 0 && return -1
        end
    elseif enc == ENC_ANSI
        mb = _wcrtomb(c, stream_mbstate!(s))
        if mb === nothing
            reperror(c, s) < 0 && return -1
        else
            for x in mb
                put_byte(Int(x), s) < 0 && return -1
            end
        end
    elseif enc == ENC_UTF8
        if c < 128
            put_byte(c, s) < 0 && return -1
        else
            buf = UInt8[]
            utf8_put_char(buf, c)
            for b in buf
                put_byte(Int(b), s) < 0 && return -1
            end
        end
    elseif enc == ENC_UTF16BE
        put_utf16(c, s, true) < 0 && return -1
    elseif enc == ENC_UTF16LE
        put_utf16(c, s, false) < 0 && return -1
    elseif enc == ENC_WCHAR
        w = UInt32(c & 0xffffffff)              # `pl_wchar_t chr = c`
        for k in 0:3                            # its bytes, in memory order
            sh = ENDIAN_BOM == 0x04030201 ? 8k : 8 * (3 - k)
            put_byte(Int((w >> sh) & 0xff), s) < 0 && return -1
        end
    else                                    # ENC_UNKNOWN (upstream's `default: assert(0)`)
        return -1
    end
    s.lastc = c
    if c == Int('\n') && (s.flags & SIO_LBUF) != 0
        S__flushbuf(s) < 0 && return -1
    end
    return S__updatefilepos(s, c)
end

# PORT: pl-stream.c Sputcode
# DIVERGES: no `tee`.
"Write character `c` to `s`, a newline as `\\r\\n` in DOS mode: `c`, or -1 on error (pl-stream.c)."
function Sputcode(c::Int, s::IOSTREAM)::Int
    c < 0 && return reperror(c, s)
    if c == Int('\n') && (s.flags & SIO_TEXT) != 0 && s.newline == SIO_NL_DOS &&
        s.lastc != Int('\r')
        put_code(Int('\r'), s) < 0 && return -1
    end
    return put_code(c, s)
end

# PORT: pl-stream.c Scanrepresent
# DIVERGES: ENC_ANSI is libc's `wcrtomb` on a fresh state under the process's LC_CTYPE (`_wcrtomb`).
"0 if `s`'s encoding can represent `c`, else -1 (pl-stream.c)."
function Scanrepresent(c::Int, s::IOSTREAM)::Int
    enc = s.encoding
    if enc == ENC_OCTET || enc == ENC_ISO_LATIN_1
        return c <= 0xff ? 0 : -1
    elseif enc == ENC_ASCII
        return c < 0x7f ? 0 : -1
    elseif enc == ENC_ANSI
        return _wcrtomb(c, zeros(UInt64, MBSTATE_WORDS)) === nothing ? -1 : 0   # a fresh `mbstate_t`, as upstream's local `state`
    elseif enc == ENC_UTF16BE || enc == ENC_UTF16LE
        return IS_UTF16_SURROGATE(c) ? -1 : 0      # SIZEOF_WCHAR_T > 2
    elseif enc == ENC_WCHAR || enc == ENC_UTF8
        return 0
    end
    return -1                                   # upstream's `default: assert(0); return -1`
end

# PORT: pl-stream.c get_ucs2
"Read one 16-bit unit from `s`, big endian when `be`: -1 at end of file (pl-stream.c)."
function get_ucs2(s::IOSTREAM, be::Bool)::Int
    c1 = get_byte(s)
    c1 == EOF && return -1
    c2 = get_byte(s)
    if c2 == EOF
        Sseterr(s, SIO_WARN, "EOF in unicode character")
        return UTF8_MALFORMED_REPLACEMENT
    end
    return be ? (c1 << 8) + c2 : (c2 << 8) + c1
end

# PORT: pl-stream.c get_utf16
"Read one UTF-16 character from `s`, joining a surrogate pair (pl-stream.c): -1 at end of file."
function get_utf16(s::IOSTREAM, be::Bool)::Int
    c = get_ucs2(s, be)
    if IS_UTF16_LEAD(c)
        c2 = get_ucs2(s, be)
        if c2 == EOF
            Sseterr(s, SIO_WARN, "EOF in unicode character")
            return UTF8_MALFORMED_REPLACEMENT
        elseif !IS_UTF16_TRAIL(c2)
            Sseterr(s, SIO_WARN, "Illegal UTF-16 continuation")
            return UTF8_MALFORMED_REPLACEMENT
        end
        return utf16_decode(c, c2)
    elseif IS_UTF16_TRAIL(c)
        Sseterr(s, SIO_WARN, "Lone UTF-16 trail surrogate")
        return UTF8_MALFORMED_REPLACEMENT
    end
    return c
end

# PORT: pl-stream.c Sgetcode (the ENC_WCHAR case)
# DIVERGES: the 4-byte `wchar_t` of this platform (SIZEOF_WCHAR_T == 4), in the machine's byte order, as a signed 32-bit value.
"The next ENC_WCHAR code of `s`: -1 at end of file, the replacement character after a partial one (pl-stream.c)."
function get_wchar(s::IOSTREAM)::Int
    w = UInt32(0)
    for n in 0:3
        c1 = get_byte(s)
        if c1 == EOF
            n == 0 && return -1
            Sseterr(s, SIO_WARN, "EOF in UCS character")
            return UTF8_MALFORMED_REPLACEMENT
        end
        w |= UInt32(c1 & 0xff) << (ENDIAN_BOM == 0x04030201 ? 8n : 8 * (3 - n))
    end
    return Int(reinterpret(Int32, w))
end

# PORT: pl-stream.c Sgetcode
# DIVERGES: ENC_ANSI is libc's `mbrtowc` under the process's LC_CTYPE, byte by byte on the stream's `mbstate` (`_mbrtowc`);
# `ENC_WCHAR` is the 4-byte native `wchar_t` (upstream's `#else` arm; `get_wchar`); no `tee`.
"The next character of `s` in its encoding, or -1 at end of file (pl-stream.c)."
function Sgetcode(s::IOSTREAM)::Int
    while true                                  # retry:
        enc = s.encoding
        if enc == ENC_OCTET || enc == ENC_ISO_LATIN_1
            c = get_byte(s)
        elseif enc == ENC_ASCII
            c = get_byte(s)
            c > 128 && Sseterr(s, SIO_WARN, "non-ASCII character")
        elseif enc == ENC_UTF8
            c = get_byte(s)
            if c != EOF && (c & 0x80) != 0
                extra = UTF8_FBN(c)
                if extra < 0
                    Sseterr(s, SIO_WARN, "Illegal UTF-8 start")
                    c = UTF8_MALFORMED_REPLACEMENT
                else
                    code = UTF8_FBV(c, extra)
                    malformed = false
                    while extra > 0
                        c2 = get_byte(s)
                        if !ISUTF8_CB(c2)
                            Sseterr(s, SIO_WARN, "Illegal UTF-8 continuation")
                            c = UTF8_MALFORMED_REPLACEMENT
                            Sungetc(c2, s)
                            malformed = true
                            break
                        end
                        code = (code << 6) + (c2 & 0x3f)
                        extra -= 1
                    end
                    if !malformed
                        if IS_UTF16_SURROGATE(code)
                            Sseterr(s, SIO_WARN, "UTF-8 surrogate code point")
                            c = UTF8_MALFORMED_REPLACEMENT
                        else
                            c = code
                        end
                    end
                end
            end
        elseif enc == ENC_UTF16BE
            c = get_utf16(s, true)
        elseif enc == ENC_UTF16LE
            c = get_utf16(s, false)
        elseif enc == ENC_WCHAR
            c = get_wchar(s)
        elseif enc == ENC_ANSI
            st = stream_mbstate!(s)
            n = 0                                               # as upstream: `n` is never incremented, so the EOF-in-sequence arm below
            # cannot be taken (probed on the pin: a lone 0xc3 at EOF reads as -1, no warning)
            c = 0
            b1 = UInt8[0]
            while true
                c = get_byte(s)
                if c == EOF
                    if n != 0
                        Sseterr(s, SIO_WARN, "EOF in multibyte Sequence")
                        c = UTF8_MALFORMED_REPLACEMENT          # mberr:
                    end
                    break                                       # n == 0: goto out, c is EOF
                end
                b1[1] = UInt8(c)
                rc, wc = _mbrtowc(b1, 1, 1, st)
                if rc == 1 || rc == 0
                    c = wc
                    break
                elseif rc == -1
                    Sseterr(s, SIO_WARN, "Illegal multibyte Sequence")
                    c = UTF8_MALFORMED_REPLACEMENT              # mberr:
                    break
                end                                             # else -2: incomplete
            end
        else
            c = -1                                              # ENC_UNKNOWN: upstream's `default: assert(0)`
        end
        # out:
        if c == Int('\r') && (s.flags & SIO_TEXT) != 0
            if s.newline == SIO_NL_DETECT
                s.newline = SIO_NL_DOS
                continue
            elseif s.newline == SIO_NL_DOS
                continue
            end
        end
        return S__updatefilepos(s, c)
    end
end

# PORT: pl-stream.c Speekcode
"The next character of `s`, left unread, or -1 at end of file (pl-stream.c)."
function Speekcode(s::IOSTREAM)::Int
    safe = -1
    if s.buffer == 0
        (s.flags & SIO_NBUF) != 0 && return -1
        S__setbuf(s, nothing, 0) == -1 && return -1
    end
    (s.flags & SIO_FEOF) != 0 && return -1
    if s.bufp + UNDO_SIZE > s.limitp && (s.flags & SIO_USERBUF) == 0
        safe = s.limitp - s.bufp
        copyto!(s.mem, s.buffer - safe, s.mem, s.bufp, safe)
    end
    start = s.bufp
    if s.position !== nothing
        psave = s.position
        s.position = nothing
        c = Sgetcode(s)
        s.position = psave
    else
        c = Sgetcode(s)
    end
    Sferror(s) != 0 && return -1
    s.flags &= ~(SIO_FEOF | SIO_FEOF2)
    if s.bufp > start
        s.bufp = start
    elseif c != -1
        @assert safe != -1
        s.bufp = s.buffer - safe
    end
    return c
end

# ── errors ──────────────────────────────────────────────────────────────────────────────────────

# PORT: pl-stream.c Sfeof
"Is `s` at its end: true, false, or -1 for an unbuffered stream (pl-stream.c)."
function Sfeof(s::IOSTREAM)::Int
    (s.flags & SIO_FEOF) != 0 && return 1
    s.bufp < s.limitp && return 0
    (s.flags & SIO_NBUF) != 0 && return -1
    S__fillbuf(s) == -1 && return 1
    s.bufp -= 1
    return 0
end

# PORT: pl-stream.c S__seterror
# DIVERGES: only a filter's function set can have a message of its own (`SIO_LASTERROR`, `S_control`); `io_errno` is not
# kept (no errno).
"Mark `s` as in error, unless it is already (pl-stream.c)."
function S__seterror(s::IOSTREAM)::Int
    (s.flags & SIO_FERR) != 0 && return 0       # error already set
    if (s.flags & SIO_CLOSING) == 0 && s.functions == Sfilterfunctions   # s->handle is not already invalid
        msg = Ref{Union{Nothing, String}}(nothing)
        if S_control(s, SIO_LASTERROR, msg) == 0
            Sseterr(s, SIO_FERR, msg[])
            return 0
        end
    end
    Sseterr(s, SIO_FERR, nothing)
    return 0
end

# PORT: pl-stream.c Sferror
"1 if `s` is in error, 0 if not, -1 if it is not a stream (pl-stream.c)."
function Sferror(s::IOSTREAM)::Int
    s.magic == SIO_MAGIC && return (s.flags & SIO_FERR) != 0 ? 1 : 0
    return -1
end

# PORT: pl-stream.c Sfpasteof
"1 if `s` was read past its end and that is an error, else 0; -1 if not a stream (pl-stream.c)."
function Sfpasteof(s::IOSTREAM)::Int
    s.magic == SIO_MAGIC &&
        return (s.flags & (SIO_FEOF2ERR | SIO_FEOF2)) == (SIO_FEOF2ERR | SIO_FEOF2) ? 1 : 0
    return -1
end

# PORT: pl-stream.c SIO_ERROR_FLAGS
"The flags `Sclearerr` clears (pl-stream.c)."
const SIO_ERROR_FLAGS = SIO_FEOF | SIO_WARN | SIO_FERR | SIO_FEOF2 | SIO_TIMEOUT

# PORT: pl-stream.c Sclearerr
"Clear `s`'s error state, and that of every stream it filters (`downstream`) (pl-stream.c)."
function Sclearerr(s::IOSTREAM)::Nothing
    us::Union{Nothing, IOSTREAM} = s
    while us !== nothing && us.magic == SIO_MAGIC
        us.flags &= ~SIO_ERROR_FLAGS
        us.io_errno = 0
        Sseterr(us, UInt32(0), nothing)
        Sset_exception(us, nothing)
        us = us.downstream
    end
    return nothing
end

# PORT: pl-stream.c Sset_exception
# DIVERGES: the core of it: the exception is a `StreamException{T}` already recorded (`record_t` of upstream's `term_t`: the recording
# and the clearing of an equal pending exception are src/os/pl-file.jl's wrapper, `Sset_exception(ld, s, ex)`); `ex === nothing` is
# upstream's `ex == 0`. Ported as is: `upstream` is not followed (only `s`
# itself is changed); a stream whose magic is wrong answers -1 (`errno = EINVAL`).
"Record `ex` as the pending exception of `s` and set `SIO_FERR`, or with `nothing` drop it and clear `SIO_FERR` and `SIO_WARN`: 0, -1 on a closed stream (pl-stream.c)."
function Sset_exception(s::IOSTREAM, ex::Union{Nothing, AbstractStreamException})::Int
    s.magic == SIO_MAGIC || return -1
    nflags = ex !== nothing ? ((s.flags & ~SIO_WARN) | SIO_FERR) : (s.flags & ~(SIO_FERR | SIO_WARN))
    s.exception = ex === nothing ? nothing : Ref{AbstractStreamException}(ex)
    s.flags = nflags
    return 0
end

# PORT: pl-stream.c Sseterr
"Set the error flags (`SIO_WARN`, `SIO_FERR`) and message of `s` and of every filter on it (`upstream`) (pl-stream.c)."
function Sseterr(s::IOSTREAM, flags::UInt32, message::Union{Nothing, String})::Int
    us::Union{Nothing, IOSTREAM} = s
    while us !== nothing && us.magic == SIO_MAGIC
        us.flags = (us.flags & ~(SIO_WARN | SIO_FERR)) | flags
        us.message = message
        (us.flags & SIO_WARN) != 0 && @assert us.message !== nothing
        us = us.upstream
    end
    us === nothing && return 0
    return -1                                   # errno = EINVAL
end

# PORT: pl-stream.c Sflush
"Write out `s`'s buffered output: 0, or -1 on error (pl-stream.c)."
function Sflush(s::IOSTREAM)::Int
    if s.buffer != 0 && (s.flags & SIO_OUTPUT) != 0
        S__flushbuf(s) < 0 && return -1
        if s.functions == Sfilterfunctions
            rc = S_control(s, SIO_FLUSHOUTPUT, nothing)
            rc != SCONTROL_NONE && rc < 0 && return -1
        end
    end
    return 0
end

# PORT: pl-stream.c Sunlock
# DIVERGES: no locks and no temporary buffer (`S__lock` gives an unbuffered output stream one for the time of
# the lock): this is the step of the last release only, which writes out an unbuffered output stream's bytes.
# The kernel writes them one by one to the handle (`S__flushbufc`), and a Julia IO holds them in its own buffer
# until `Sflush_julia_io` writes them out here; a failure is the stream's error (`S__seterror`) and -1.
"Release `s`: an unbuffered output stream is written out; 0, or -1 if that failed (pl-stream.c)."
function Sunlock(s::IOSTREAM)::Int
    rval = 0
    if (s.flags & (SIO_NBUF | SIO_OUTPUT)) == (SIO_NBUF | SIO_OUTPUT)
        rval = S__removebuf(s)
        h = s.handle
        if s.functions == Siofunctions && h isa Sjulia_io && Sflush_julia_io(h) < 0
            S__seterror(s)
            rval = -1
        end
    end
    return rval
end

# ── creating and closing ────────────────────────────────────────────────────────────────────────

# PORT: pl-stream.c Snew
# DIVERGES: a text stream's encoding and `unicode_atoms` are `initEncoding()` and `initUnicodeAtoms()` (pl-stream.c:3544-3545,
# `LD->encoding` and `LD->unicode_atoms`): the stream layer has no local data (`GET_LD`), so a caller that has one passes them
# as `enc` and `uatoms` (`ld.encoding`, `ld.unicode_atoms`); the defaults are the kernel's UTF-8 and `accept`; no mutex, no file
# number; `initStreamLocale(s)` is NOT called here (it needs the database): the callers that have one call it
# (`initStreamLocale`, src/os/pl-locale.jl), so a stream made by `Snew` alone has `locale == nothing` (a filter stream included).
"A new stream over `handle` with `functions`, its flags `flags` (pl-stream.c)."
function Snew(
    handle::Union{Nothing, memfile, IOSTREAM, Sjulia_io}, flags::UInt32,
    functions::IOFUNCTIONS, enc::IOENC = ENC_UTF8,
    uatoms::Sunicode_atoms_t = S_UATOMS_ACCEPT
)::IOSTREAM
    s = IOSTREAM()
    s.magic = SIO_MAGIC
    s.lastc = EOF
    s.flags = flags
    s.handle = handle
    s.functions = functions
    s.posbuf.lineno = 1
    if (flags & SIO_TEXT) != 0
        s.encoding = enc                            # initEncoding()
        s.unicode_atoms = uatoms                    # initUnicodeAtoms()
    else
        s.encoding = ENC_OCTET
    end
    (flags & SIO_RECORDPOS) != 0 && (s.position = s.posbuf)
    return s
end

# PORT: pl-stream.c Snew
# DIVERGES: the functions are the `AbstractSfilter` `impl` (the context and the callbacks together, where upstream gives a context
# and a table), `functions` must be `Sfilterfunctions`; the stream has no `handle`.
"A new stream over the filter functions `impl` (a `Snew(ctx, flags, &myfunctions)` of a package such as zlib4pl.c) (pl-stream.c)."
function Snew(impl::AbstractSfilter, flags::UInt32, functions::IOFUNCTIONS)::IOSTREAM
    @assert functions == Sfilterfunctions
    s = Snew(nothing, flags, functions)
    s.filter = Ref{AbstractSfilter}(impl)
    s.fileno = S__fileno(s)
    return s
end

# PORT: pl-stream.c Sset_filter
# DIVERGES: `filter->timeout = parent->timeout` is absent (the kernel has no timeouts); `unallocStream` frees nothing (Julia's
# GC owns the stream), `Srelease` only says whether it would have.
"""
Link `filter` to `parent` in a pipeline, or unlink the one on `parent` if `filter` is `nothing`: 0, or -1 (pl-stream.c).
If `parent` is an output stream: application -> filter -> parent; if it is an input stream: parent -> filter -> application.
The filter is referenced, so it is not freed, even if it is closed.
"""
function Sset_filter(parent::IOSTREAM, filter::Union{Nothing, IOSTREAM})::Int
    parent.magic != SIO_MAGIC && return -1                      # errno = EINVAL
    if filter !== nothing                                       # set filter
        filter.magic != SIO_MAGIC && return -1                  # errno = EINVAL
        Sreference(filter)
        Sreference(parent)
        @assert parent.upstream === nothing && filter.downstream === nothing
        parent.upstream = filter
        filter.downstream = parent
    else                                                        # clear filter
        f = parent.upstream
        if f !== nothing
            @assert f.downstream === parent
            f.downstream = nothing
            parent.upstream = nothing
            Srelease(f)                                         # unallocStream() if erased and unreferenced
            Srelease(parent)
        end
    end
    return 0
end

# PORT: pl-stream.c S__close
# DIVERGES: no locks, no close hooks (the closers call pl-file.c's `freeStream`,
# src/os/pl-file.jl), no `reportStreamError` on a failed close or on the lock of an upstream filter (the closers do); the stream is
# marked closed, and `erased` when a reference is held.
"Close `s`: 0, or -1 on error (pl-stream.c)."
function S__close(s::IOSTREAM)::Int
    rval = 0
    s.magic != SIO_MAGIC && return -1           # already closed!?
    (s.flags & SIO_CLOSING) != 0 && return rval # recursive
    if s.upstream !== nothing                   # a filter sits on this stream: it closes it
        Sseterr(s, SIO_FERR, "Locked by upstream filter")
        Sunlock(s)
        return -1
    end
    s.flags |= SIO_CLOSING
    rval = S__removebuf(s)
    if S_close(s) < 0
        S__seterror(s)
        rval = -1
    end
    s.magic = SIO_CMAGIC
    s.message = nothing
    slo = s.locale                              # `if ( s->locale ) releaseLocale(s->locale)`: a local, so the
    if slo !== nothing                          # nothing-test narrows the type (JET cannot narrow a mutable field)
        releaseLocale(slo)
        s.locale = nothing
    end
    s.references == 0 || (s.erased = true)      # else unallocStream(): Julia's GC frees it
    return rval
end

# PORT: pl-stream.c Ssetlocale
# DIVERGES: `old` is the return value (upstream's `PL_locale **old`), `Sset_locale`'s 0 is the `Nothing`.
"Make `new` (`nothing`: none) the locale of `s`; the locale it had (pl-stream.c)."
function Ssetlocale(s::IOSTREAM, new::Union{Nothing, IOLocale})::Union{Nothing, IOLocale}
    lo = s.locale
    new === lo && return lo
    s.locale = new === nothing ? nothing : acquireLocale(new)::IOLocale
    lo === nothing || releaseLocale(lo)
    return lo
end

# PORT: pl-stream.c Sclose
"Close `s`: 0, or -1 on error (pl-stream.c)."
Sclose(s::IOSTREAM)::Int = S__close(s)

# ORIGINAL: pl-stream.c's `Sreference` macro (pl-stream.h): no atomic increment (no threads).
"Count one more reference to `s` (SWI-Stream.h)."
Sreference(s::IOSTREAM)::Int = (s.references += 1)

# ORIGINAL: pl-stream.c's `Sunreference` macro (pl-stream.h): no atomic decrement (no threads).
"Count one reference to `s` less: the references left (SWI-Stream.h)."
Sunreference(s::IOSTREAM)::Int = (s.references -= 1)

# PORT: pl-stream.c Sacquire
"Take a reference to `s`, which keeps a closed stream from being freed (pl-stream.c)."
function Sacquire(s::IOSTREAM)::IOSTREAM
    Sreference(s)
    return s
end

# PORT: pl-stream.c Srelease
# DIVERGES: `unallocStream` frees nothing (Julia's GC owns the stream): the result says whether it
# would have.
"Release a reference to `s`; true if `s` was erased and this was the last (pl-stream.c)."
function Srelease(s::IOSTREAM)::Bool
    return Sunreference(s) == 0 && s.erased
end

# PORT: pl-stream.c Scontrol_file as Scontrol_getsize (the `SIO_GETSIZE` action; and Scontrol_memfile's)
# DIVERGES: the `control` function of the stream's set, called for `SIO_GETSIZE` alone: -1 where upstream's `control` is NULL
# or fails. A file (`IOStream`) is `fstat`'s `st_size`; an `IOBuffer`, which stands in for a file, the size of its data;
# a terminal or a pipe on stdio `fstat`'s 0. A memory file answers `mf->here`, as upstream's `Scontrol_memfile` does (not its
# size). A filter (`Sfilterfunctions`) answers what its `control` does. A `popen` pipe (`Spipefunctions`: `Scontrol_pipe` has no `SIO_GETSIZE`), a null stream and a string stream have none.
"The size `SIO_GETSIZE` reports for `s`'s handle, or -1."
function Scontrol_getsize(s::IOSTREAM)::Int64
    if s.functions == Sfilterfunctions                          # a filter's own `control` (INT-MERGE-16: the tip's Ssize arm)
        size = Ref(Int64(0))
        S_control(s, SIO_GETSIZE, size) == 0 && return size[]
        return Int64(-1)
    end
    h = s.handle
    if s.functions == Smemfunctions && h isa memfile
        return Int64(h.here)
    elseif s.functions == Siofunctions && h isa Sjulia_io
        h.proc !== nothing && return Int64(-1)                  # Scontrol_pipe
        io = h.io
        try
            if io isa IOStream
                return Int64(filesize(io))
            elseif io isa IOBuffer
                here = position(io)
                seekend(io)
                size = position(io)
                seek(io, here)
                return Int64(size)
            end
            return Int64(0)                                     # a terminal or a pipe
        catch e
            e isa Union{SystemError, Base.IOError, ArgumentError} || rethrow()
            return Int64(-1)
        end
    end
    return Int64(-1)
end

# PORT: pl-stream.c Ssize
# DIVERGES: the `control` call is `Scontrol_getsize`; any other stream with a seek function is measured by seeking to its
# end and back (upstream's second branch); one without sets `ESPIPE` as upstream.
"The size of the data object `s` reads or writes, or -1 (pl-stream.c)."
function Ssize(s::IOSTREAM)::Int64
    size = Scontrol_getsize(s)                                  # functions->control: SIO_GETSIZE
    size >= 0 && return size
    if S_has_seek(s)
        here = Stell64(s)
        local enddata::Int64
        if Sseek64(s, Int64(0), SIO_SEEK_END) == 0
            enddata = Stell64(s)
        else
            enddata = Int64(-1)
        end
        Sseek64(s, here, SIO_SEEK_SET)

        return enddata
    end

    s.io_errno = ESPIPE
    S__seterror(s)
    return Int64(-1)
end

# ── seek (pl-stream.c) ──────────────────────────────────────────────────────────────────────────

# ORIGINAL: Linux's `ESPIPE` (illegal seek), the value `Sseek64` records where the stream has no seek function.
const ESPIPE = 29

# PORT: pl-stream.c Sunit_size
# DIVERGES: `sizeof(wchar_t)` is 4 (Linux); the enum has no other member to assert on.
"The size in bytes of one unit of the stream's encoding (pl-stream.c)."
function Sunit_size(s::IOSTREAM)::Int
    enc = s.encoding
    (enc == ENC_UTF16BE || enc == ENC_UTF16LE) && return 2
    enc == ENC_WCHAR && return 4
    return 1
end

# ORIGINAL: whether the stream's function set has a `seek` or `seek64` (upstream tests the function pointers):
# the memory functions, the null functions and a Julia IO that is not a `popen` pipe (upstream's `Sfilefunctions` and
# `Sttyfunctions` seek with `lseek`, which says ESPIPE for a pipe or a terminal; `Spipefunctions` has no seek:
# `Sjulia_io.proc` marks it); the string and stderr functions have none.
"Whether the stream's function set can seek."
function S_has_seek(s::IOSTREAM)::Bool
    f = s.functions
    (f == Smemfunctions || f == Snullfunctions) && return true
    if f == Siofunctions
        h = s.handle
        return h isa Sjulia_io && h.proc === nothing
    end
    return false
end

# PORT: pl-stream.c Sseek_file64 as Sseek_julia_io
# DIVERGES: seeks a Julia IO where upstream calls `lseek(fd, pos, whence)`, never libc's `lseek` (it would ignore
# the IO's own buffer: Julia's `seek`, `position` and `seekend` do not). A file (`IOStream`) may be seeked past its
# end as `lseek` allows, but not before its start (EINVAL, nothing moved); a buffer (`IOBuffer`), which
# Julia's `seek` clamps without a word, is bounds-checked: a position before its start or after its end is EINVAL;
# a terminal or a pipe is not seekable (ESPIPE, as `lseek` says); a closed IO is EBADF. The reason is left in
# `s.io_errno`, where upstream leaves it in `errno`.
"Seek the Julia IO `h` holds to `pos` as `whence` says: the new position, or -1 with `s.io_errno` set."
function Sseek_julia_io(s::IOSTREAM, h::Sjulia_io, pos::Int64, whence::Int)::Int64
    io = h.io
    if io isa IOStream || io isa IOBuffer
        try
            here = Int64(position(io))
            if io isa IOStream
                size = Int64(-1)                        # `lseek` allows a seek past the end
            else
                seekend(io)
                size = Int64(position(io))
                seek(io, here)
            end
            if whence == SIO_SEEK_SET
                target = pos
            elseif whence == SIO_SEEK_CUR
                target = here + pos
            elseif whence == SIO_SEEK_END
                if io isa IOStream
                    seekend(io)
                    size = Int64(position(io))
                    seek(io, here)                      # a failed seek leaves the position
                end
                target = size + pos
            else
                s.io_errno = EINVAL
                return Int64(-1)
            end
            if target < 0 || (io isa IOBuffer && target > size)
                s.io_errno = EINVAL
                return Int64(-1)
            end
            target == here || seek(io, target)
            return target
        catch e
            e isa Union{SystemError, Base.IOError, ArgumentError} || rethrow()
            s.io_errno = if e isa SystemError
                Int(e.errnum)
            elseif e isa Base.IOError
                -Int(e.code)
            else
                io isa IOBuffer ? ESPIPE : EBADF        # not seekable / closed
            end
            return Int64(-1)
        end
    end
    s.io_errno = ESPIPE                                 # a terminal or a pipe: ESPIPE
    return Int64(-1)
end

# ORIGINAL: `(*s->functions->seek64)(s->handle, pos, whence)`: the function set's seek, on its handle; -1 for a set with none.
# DIVERGES: where upstream's backend leaves the reason in the global `errno` (`Sseek_memfile64`: EINVAL; `lseek`: ESPIPE, EINVAL,
# EBADF), this sets `s.io_errno` at each failure, and the callers (`Sseek64`, `Stell64`, pl-file.c's seek/4 and
# set_stream_position/2) read that field where upstream reads `errno`. `Sseek_null` leaves none: its failure is EINVAL. A set
# whose seek is NULL (`Sstringfunctions`, `Sstderrfunctions`) fails with ESPIPE.
"Seek `s`'s handle to `pos` as `whence` (`SIO_SEEK_*`) says: the new position, or -1 with `s.io_errno` set."
function S_seek64(s::IOSTREAM, pos::Int64, whence::Int)::Int64
    h = s.handle
    if s.functions == Smemfunctions && h isa memfile
        r = Sseek_memfile64(h, pos, whence)
        r < 0 && (s.io_errno = EINVAL)                  # Sseek_memfile64: errno = EINVAL
        return r
    end
    if s.functions == Siofunctions && h isa Sjulia_io
        return Sseek_julia_io(s, h, pos, whence)
    end
    if s.functions == Snullfunctions
        r = Int64(Sseek_null(Int(pos), whence))
        r < 0 && (s.io_errno = EINVAL)
        return r
    end
    s.io_errno = ESPIPE
    return Int64(-1)
end

# ORIGINAL: the label `update:` of `Sseek64`: the stream is repositioned to `pos`.
"Record that `s` now stands at byte `pos`: off its end, its line number and column left alone (pl-stream.c `update:`)."
function S__seek_update(s::IOSTREAM, pos::Int64)::Int
    s.flags &= ~(SIO_FEOF | SIO_FEOF2)                             # not on eof of file anymore

    p = s.position
    if p !== nothing
        s.flags |= (SIO_NOLINENO | SIO_NOLINEPOS)                  # no update this
        Sresetesc(p)
        p.byteno = pos
        p.charno = div(pos, Sunit_size(s))                         # compatibility
    end

    return 0
end

# PORT: pl-stream.c Sseek64
# DIVERGES: the `goto update` is `S__seek_update`; a set carries `seek64` alone (the 32-bit `seek` is one function
# of the same body), so the branch with the `LONG_MAX` test and its `EINVAL` is unwritten; `errno` is the stream's
# `io_errno`: `ESPIPE` is set here for a set with no seek function, the reason of a seek that failed by `S_seek64`; the
# position `s.position` is `s.posbuf` or `nothing`; `nbufp` is an index into `mem`.
"""
Re-position the stream to byte `pos` (`whence`): 0, or -1 (pl-stream.c). First tries to move the read pointer in the
buffer; else flushes, drops the buffer and asks the function set.
"""
function Sseek64(s::IOSTREAM, pos::Int64, whence::Int)::Int
    if (s.flags & SIO_INPUT) != 0 && s.limitp > s.buffer           # something there
        now = Stell64(s)

        if now != -1
            nbufp = -1
            newpos = Int64(-1)

            if whence == SIO_SEEK_CUR
                nbufp = s.bufp + pos
                newpos = now + pos
            elseif whence == SIO_SEEK_SET
                nbufp = s.bufp + (pos - now)
                newpos = pos
            else
                newpos = -1                                        # should not happen
            end

            if nbufp >= s.buffer && nbufp < s.limitp
                s.bufp = Int(nbufp)

                return S__seek_update(s, newpos)
            end
        end
    end

    if !S_has_seek(s)
        s.io_errno = ESPIPE
        S__seterror(s)
        return -1
    end

    Sflush(s)

    s.bufp = s.buffer
    (s.flags & SIO_INPUT) != 0 && (s.limitp = s.buffer)

    if whence == SIO_SEEK_CUR
        pos += Stell64(s)
        whence = SIO_SEEK_SET
    end

    pos = S_seek64(s, pos, whence)

    if pos < 0
        S__seterror(s)
        return -1
    end

    return S__seek_update(s, pos)
end

# PORT: pl-stream.c Stell64
# DIVERGES: as `Sseek64`, `errno` is `s.io_errno` (`EINVAL`: neither a position nor a seek function).
"The current position in the file in bytes, or -1 (pl-stream.c)."
function Stell64(s::IOSTREAM)::Int64
    p = s.position
    if p !== nothing
        return p.byteno
    elseif S_has_seek(s)
        pos = S_seek64(s, Int64(0), SIO_SEEK_CUR)

        if s.buffer != 0                                           # open
            off = Int64(s.bufp - s.buffer)

            (s.flags & SIO_INPUT) != 0 && (off -= s.limitp - s.buffer)

            pos += off
        end

        return pos
    else
        s.io_errno = EINVAL
        S__seterror(s)
        return -1
    end
end

# PORT: pl-stream.c Sseek
"`Sseek64` with a `long` position (pl-stream.c)."
Sseek(s::IOSTREAM, pos::Int, whence::Int)::Int = Sseek64(s, Int64(pos), whence)

# PORT: pl-stream.c Stell
# DIVERGES: the errno of the failure is left in `s.io_errno` (see `S_seek64`).
"`Stell64` as a `long`: -1 if the position is not (pl-stream.c)."
function Stell(s::IOSTREAM)::Int
    pos = Stell64(s)
    pos == -1 && return -1
    pos <= typemax(Clong) && return Int(pos)
    s.io_errno = EINVAL
    S__seterror(s)
    return -1
end

# PORT: pl-stream.c Sfgets
# DIVERGES: `buf` is a byte vector of at least `n` bytes, the result is `buf` or `nothing` (upstream's NULL); the
# terminating NUL is the byte 0x00 in `buf`.
"Read a line of at most `n` bytes into `buf`, newline included: `buf`, or `nothing` at end of file (pl-stream.c)."
function Sfgets(buf::Vector{UInt8}, n::Int, s::IOSTREAM)::Union{Nothing, Vector{UInt8}}
    q = 1
    while n > 0
        n -= 1
        c = Sgetc(s)
        if c == EOF
            buf[q] = 0x00
            return q == 1 ? nothing : buf
        else
            buf[q] = c % UInt8
            q += 1
            if c == Int('\n')
                n > 0 && (buf[q] = 0x00)
                return buf
            end
        end
    end
    return buf
end

# PORT: pl-stream.c Sfputs
# DIVERGES: the C string is a byte vector up to its first 0x00, or a `String` (its UTF-8 bytes).
"Write the bytes of the C string `q` as characters: 0, or -1 (EOF) on error (pl-stream.c)."
function Sfputs(q::AbstractVector{UInt8}, s::IOSTREAM)::Int
    for b in q
        b == 0x00 && break
        Sputcode(Int(b), s) < 0 && return EOF
    end
    return 0
end
Sfputs(q::String, s::IOSTREAM)::Int = Sfputs(codeunits(q), s)

# PORT: pl-stream.c Sfree
# DIVERGES: nothing is freed (Julia's GC owns the memory upstream's `free()` returns).
"Free memory the stream layer allocated (pl-stream.c)."
Sfree(ptr)::Nothing = nothing

# ── pending input (pl-stream.c) ─────────────────────────────────────────────────────────────────
# `Sread_pending`, `SIO_RP_BLOCK` and `SIO_RP_NOPOS` are defined once, in the filter-stream section above (INT-2: wip/stream-filter and
# lane D (wip/rec-enc1) each ported them; the STREAMX copy is kept, its two flag constants made `Int` as lane D's were, because the
# function takes `flags::Int` and read_pending_codes/3 and the tests pass the constants directly).

# PORT: pl-stream.c bomdefs
"The byte order marks `ScheckBOM` recognises: the encoding they announce and their bytes (pl-stream.c)."
const bomdefs = (
    (ENC_UTF8, (0xef, 0xbb, 0xbf)),
    (ENC_UTF16BE, (0xfe, 0xff)),
    (ENC_UTF16LE, (0xff, 0xfe))
)

# PORT: pl-stream.c ScheckBOM
# DIVERGES: -1 where upstream sets `errno = EINVAL` (a non-buffered stream).
"Detect a byte order mark at the start of the input stream `s`, switch to its encoding and skip it: 0, or -1 (pl-stream.c)."
function ScheckBOM(s::IOSTREAM)::Int
    (s.flags & SIO_NBUF) != 0 && return -1                  # errno = EINVAL
    while true
        avail = s.limitp - s.bufp
        for (enc, bom) in bomdefs
            n = length(bom)
            if avail >= n && all(i -> s.mem[s.bufp + i - 1] == bom[i], 1:n)
                s.encoding = enc
                s.bufp += n
                s.flags |= SIO_BOM
                s.position !== nothing && (s.position.byteno += n)
                return 0
            end
        end
        avail >= 4 && return 0                              # longest BOM
        if S__fillbuf(s) == -1
            s.flags &= ~SIO_FEOF
            return 0                                        # empty stream
        end
        s.bufp -= 1
    end
end

# PORT: pl-stream.c SwriteBOM
"Write a byte order mark if `s`'s encoding has one: 0, or -1 on error (pl-stream.c)."
function SwriteBOM(s::IOSTREAM)::Int
    enc = s.encoding
    if enc == ENC_UTF8 || enc == ENC_UTF16LE || enc == ENC_UTF16BE
        if Sputcode(Int(0xfeff), s) != -1
            s.flags |= SIO_BOM
            return 0
        end
        return -1
    end
    return 0
end

# ── memory files ────────────────────────────────────────────────────────────────────────────────

# PORT: pl-stream.c S__memfile_nextsize
"The size a memory file grows to, to hold `needed` bytes: 512, doubled (pl-stream.c)."
function S__memfile_nextsize(needed::Int)::Int
    size = 512
    while size < needed
        size *= 2
    end
    return size
end

# PORT: pl-stream.c Swrite_memfile
"Append the `size` bytes of `buf` from `from` to the memory file (pl-stream.c)."
function Swrite_memfile(mf::memfile, buf::Vector{UInt8}, from::Int, size::Int)::Int
    if mf.here + size + 1 >= mf.allocated
        ns = S__memfile_nextsize(mf.here + size + 1)
        old = mf.buffer
        if mf.allocated == 0 || !mf.malloced
            nb = zeros(UInt8, ns)
            if !mf.malloced
                old !== nothing && copyto!(nb, 1, old, 1, min(mf.allocated, length(old)))
                mf.malloced = true
            end
        else
            nb = zeros(UInt8, ns)               # realloc()
            old !== nothing && copyto!(nb, 1, old, 1, length(old))
        end
        mf.allocated = ns
        mf.bufferp[] = mf.buffer = nb
    end
    b = mf.buffer::Vector{UInt8}
    copyto!(b, mf.here + 1, buf, from, size)
    mf.here += size
    if mf.here > mf.size
        mf.size = mf.here
        sp = mf.sizep
        sp !== nothing && (sp[] = mf.size)      # make externally known
        b[mf.size + 1] = 0x00
    end
    return size
end

# PORT: pl-stream.c Sread_memfile
"Read up to `size` bytes of the memory file into `buf` at `from` (pl-stream.c)."
function Sread_memfile(mf::memfile, buf::Vector{UInt8}, from::Int, size::Int)::Int
    if size + mf.here > mf.size
        size = mf.here > mf.size ? 0 : mf.size - mf.here
    end
    b = mf.buffer
    size > 0 && b !== nothing && copyto!(buf, from, b, mf.here + 1, size)
    mf.here += size
    return size
end

# PORT: pl-stream.c Sseek_memfile64
"Move the memory file's position (pl-stream.c)."
function Sseek_memfile64(mf::memfile, offset::Int64, whence::Int)::Int64
    if whence == SIO_SEEK_SET
    elseif whence == SIO_SEEK_CUR
        offset += mf.here
    elseif whence == SIO_SEEK_END
        offset = mf.size - offset
    else
        return -1
    end
    (offset < 0 || offset > mf.size) && return -1
    mf.here = Int(offset)
    return offset
end

# PORT: pl-stream.c Sclose_memfile
"Close the memory file (pl-stream.c)."
function Sclose_memfile(mf::memfile)::Int
    mf.free_on_close && (mf.buffer = nothing)
    return 0
end

# PORT: pl-stream.c Sopenmem
# DIVERGES: `bufp` and `sizep` are references (a `nothing` buffer for NULL; `nothing` for no size
# reference); the buffer read in mode "r" is `bufp[]`.
"""
A stream on memory (pl-stream.c): mode `"r"` reads the `sizep[]` bytes of `bufp[]` (all of them up
to a 0 byte if `sizep` is `nothing` or -1); mode `"w"` writes into a buffer that grows, `bufp[]`
and `sizep[]` updated as it does.
"""
function Sopenmem(
    bufp::Base.RefValue{Union{Nothing, Vector{UInt8}}},
    sizep::Union{Nothing, Base.RefValue{Int}}, mode::String
)::Union{Nothing, IOSTREAM}
    flags = SIO_FBUF | SIO_RECORDPOS | SIO_NOMUTEX | SIO_TEXT
    mf = memfile(0, 0, nothing, 0, bufp[], bufp, false, false)
    i = 1
    m = codeunits(mode)
    while i <= length(m)
        c = Char(m[i])
        if c == 'r'
            flags |= SIO_INPUT
            b = mf.buffer
            if sizep === nothing || sizep[] == -1
                z = b === nothing ? nothing : findfirst(==(0x00), b)
                size = if b === nothing
                    0
                elseif z === nothing
                    length(b)
                else
                    z - 1
                end
            else
                size = sizep[]
            end
            mf.size = size
            mf.allocated = size + 1
        elseif c == 'w'
            flags |= SIO_OUTPUT
            mf.size = 0
            mf.allocated = sizep !== nothing ? sizep[] : 0
            (mf.buffer === nothing || (i < length(m) && Char(m[i + 1]) == 'a')) &&
                (mf.malloced = true)
            b = mf.buffer
            b !== nothing && !isempty(b) && (b[1] = 0x00)
            sizep !== nothing && (sizep[] = mf.size)
        elseif c == 'b'
            flags &= ~SIO_TEXT
        elseif c == 'F'
            mf.free_on_close = true
        else
            return nothing
        end
        i += 1
    end
    mf.sizep = sizep
    mf.here = 0
    s = Snew(mf, flags, Smemfunctions)
    s.newline = SIO_NL_POSIX
    return s
end

# ── strings ─────────────────────────────────────────────────────────────────────────────────────

# PORT: pl-stream.c Sread_string
"A string stream has nothing more to read (pl-stream.c)."
Sread_string(::IOSTREAM, ::Vector{UInt8}, ::Int, ::Int)::Int = 0          # signal EOF

# PORT: pl-stream.c Swrite_string
"A string stream cannot grow (pl-stream.c)."
Swrite_string(::IOSTREAM, ::Vector{UInt8}, ::Int, ::Int)::Int = -1        # signal error

# PORT: pl-stream.c Sclose_string
"Close a string stream, an output one 0-terminated (pl-stream.c)."
function Sclose_string(s::IOSTREAM)::Int
    if (s.flags & SIO_OUTPUT) != 0
        if s.bufp < s.limitp
            s.mem[s.bufp] = 0x00
            s.bufp += 1
            return 0
        end
        return -1                               # ENOSPC
    end
    return 0                                    # input string
end

# PORT: pl-stream.c Sopen_string
# DIVERGES: no static stream argument (`s`); `size` -1 reads up to the first 0 byte; Julia's GC
# owns the stream; `uatoms` is `initUnicodeAtoms()` (the stream layer has no `LD`): the caller passes `ld.unicode_atoms`.
"""
A stream on the user's byte vector `buf` (pl-stream.c): mode `"r"` reads its first `size` bytes,
`"w"` writes into it; ISO Latin-1, as upstream opens it (`Sopen_text` sets the text's encoding).
"""
function Sopen_string(
    buf::Vector{UInt8}, size::Int, mode::String, uatoms::Sunicode_atoms_t = S_UATOMS_ACCEPT
)::Union{Nothing, IOSTREAM}
    flags = SIO_FBUF | SIO_USERBUF
    s = IOSTREAM()
    s.mem = buf
    s.buffer = 1
    s.bufp = 1
    s.unbuffer = 1
    s.handle = s                                # for Sclose_string()
    s.functions = Sstringfunctions
    s.encoding = ENC_ISO_LATIN_1
    s.unicode_atoms = uatoms                    # initUnicodeAtoms() (pl-stream.c:4441): the caller's `ld.unicode_atoms`
    m = isempty(mode) ? ' ' : first(mode)
    if m == 'r'
        if size == -1
            z = findfirst(==(0x00), buf)
            size = z === nothing ? length(buf) : z - 1
        end
        flags |= SIO_INPUT
    elseif m == 'w'
        flags |= SIO_OUTPUT
    else
        return nothing
    end
    s.flags = flags
    s.limitp = 1 + size
    s.magic = SIO_MAGIC
    return s
end

# ── a Julia IO (ORIGINAL: in place of the OS file functions) ────────────────────────────────────

# PORT: pl-stream.c Sread_file as Sread_julia_io
# DIVERGES: from a Julia IO, where upstream reads a file descriptor.
"Read up to `size` bytes of the IO into `buf` at `from`: the count, 0 at its end."
function Sread_julia_io(h::Sjulia_io, buf::Vector{UInt8}, from::Int, size::Int)::Int
    io = h.io
    n = 0
    while n < size && !eof(io)
        buf[from + n] = read(io, UInt8)
        n += 1
    end
    return n
end

# PORT: pl-stream.c Swrite_file as Swrite_julia_io
# DIVERGES: to a Julia IO, where upstream writes a file descriptor; an IO that throws (closed, a
# broken pipe) is a write error, -1, as upstream's `write()` failing.
"Write the `size` bytes of `buf` from `from` to the IO: the count, or -1 on error."
function Swrite_julia_io(h::Sjulia_io, buf::Vector{UInt8}, from::Int, size::Int)::Int
    io = h.io
    try
        return write(io, view(buf, from:(from + size - 1)))
    catch e
        e isa Union{Base.IOError, ArgumentError, EOFError} || rethrow()
        return -1
    end
end

# ORIGINAL: what upstream's unbuffered `write()` does at once, for a Julia IO that buffers: the write-out `Sunlock`
# asks for. A failed `flush` of a Julia IO drops the bytes it could not write, as upstream's `S__removebuf` does at
# the failure, so a later `close` answers 0 (row pt29).
"Write out what the IO holds: 0, or -1 on error."
function Sflush_julia_io(h::Sjulia_io)::Int
    io = h.io
    try
        flush(io)
        return 0
    catch e
        e isa Union{Base.IOError, SystemError, ArgumentError, EOFError} || rethrow()
        return -1
    end
end

# PORT: pl-stream.c Sclose_file as Sclose_julia_io
# DIVERGES: closes the Julia IO only if the stream owns it; a failure of that close (the IO's last write) is -1,
# as upstream's `close()` failing: `S__close` makes it the stream's error and the closer raises it.
"Close the IO if the stream owns it: 0, or -1 on error."
function Sclose_julia_io(h::Sjulia_io)::Int
    rc = 0
    if h.close_io
        try
            close(h.io)
        catch e
            e isa Union{Base.IOError, SystemError, ArgumentError, EOFError} || rethrow()
            rc = -1
        end
    end
    proc = h.proc
    proc === nothing || wait(proc)                          # pclose(): the exit status is not looked at, as upstream
    return rc
end

# PORT: pl-stream.c Sopen_file as Sopen_julia_io
# DIVERGES: a stream on an open Julia IO (a file or a buffer), UTF-8 text, the position recorded,
# where upstream opens a file by name with mode and options.
"A text stream on `io`: mode `\"r\"` or `\"w\"`; closing it closes `io` if `close_io`."
function Sopen_julia_io(
    io::Union{IOStream, IOBuffer, Base.TTY, Base.PipeEndpoint}, mode::String, close_io::Bool
)::Union{Nothing, IOSTREAM}
    flags = SIO_FBUF | SIO_RECORDPOS | SIO_NOMUTEX | SIO_TEXT
    if mode == "r"
        flags |= SIO_INPUT
    elseif mode == "w"
        flags |= SIO_OUTPUT
    else
        return nothing
    end
    s = Snew(Sjulia_io(io, close_io), flags, Siofunctions)
    s.newline = SIO_NL_POSIX
    return s
end

# ── pipes (pl-stream.c Sopen_pipe), lane D ──────────────────────────────────────────────────────

# PORT: pl-stream.c Sopen_pipe
# DIVERGES: also `Sread_pipe`, `Swrite_pipe`, `Sclose_pipe`, `Scontrol_pipe` and `Spipefunctions` (pl-stream.c:3967-4072 at
# the pin 18168e62); the child is Julia's (`open(Cmd(["/bin/sh", "-c", command]), …)`) in place of `popen`, its pipe end a `Sjulia_io` of
# `Siofunctions` (`Sjulia_io.proc` is `pclose`'s child); a `r` child reads `/dev/null` for its stdin, a `w` child shares the process's
# stdout (file descriptor 1, as `popen`'s child inherits it: `Base.RawFD(1)`, a concrete type, where the global `Base.stdout` is
# typed `IO` and made `open`'s call a runtime dispatch under JET; `redirect_stdout` re-points descriptor 1, so the child follows it); no seek function (a pipe: `S_has_seek` is false, so `Sseek64` sets ESPIPE), `SIO_GETFILENO` has no twin. The type string:
# upstream's `popen` takes `type[0]` (`r` or `w`: another first character is EINVAL here as `popen` gives), and its `assert(0)` on a
# character other than `r`, `w`, `b` is EINVAL here. Returns `(stream, errno)` as `Sopen_file` does.
# `enc` and `uatoms` are `Snew`'s (`initEncoding()`, `initUnicodeAtoms()`: the caller's `ld.encoding`, `ld.unicode_atoms`).
"Open a `/bin/sh -c command` child as a stream: `type` is `r` or `w`, then `b` for binary; the stream and 0, or `nothing` and the errno (pl-stream.c)."
function Sopen_pipe(
    command::String, type::String, enc::IOENC = ENC_UTF8, uatoms::Sunicode_atoms_t = S_UATOMS_ACCEPT
)::Tuple{Union{Nothing, IOSTREAM}, Int}
    isempty(type) && return (nothing, EINVAL)
    mode = type[1]
    (mode == 'r' || mode == 'w') || return (nothing, EINVAL)
    flags = SIO_RECORDPOS | SIO_FBUF | SIO_TEXT
    for c in type
        if c == 'r'
            flags |= SIO_INPUT
        elseif c == 'w'
            flags |= SIO_OUTPUT
        elseif c == 'b'
            flags &= ~SIO_TEXT
        else
            return (nothing, EINVAL)
        end
    end

    proc = try
        cmd = Cmd(["/bin/sh", "-c", command])
        mode == 'r' ? open(cmd, "r", devnull) : open(cmd, "w", Base.RawFD(1))
    catch e
        e isa ArgumentError && return (nothing, EINVAL)
        e isa Base.IOError || rethrow()
        return (nothing, Int(-e.code))
    end
    io = mode == 'r' ? proc.out : proc.in
    io isa Base.PipeEndpoint || error("Sopen_pipe: the child's pipe end is a ", typeof(io))
    s = Snew(Sjulia_io(io, true, proc), flags, Siofunctions, enc, uatoms)
    return (s, 0)
end

# ── files (pl-stream.c Sopen_file), since R2's S1 ───────────────────────────────────────────────

# DIVERGES: Linux's values, as src/pl-error.jl's (EPERM, EAGAIN, EACCES, ENFILE, EMFILE, EROFS, EPIPE,
# ENAMETOOLONG, ENOTEMPTY, ELOOP: Y1); upstream uses the C library's names. The three this file adds.
# (a comment, not a docstring, for each constant)
const ENOENT = 2
const EBADF = 9
const EINVAL = 22

"The process's file creation mask (`umask(2)`, read by setting it and putting it back)."
function _current_umask()::Int
    old = ccall(:umask, Cuint, (Cuint,), 0o022)
    ccall(:umask, Cuint, (Cuint,), old)
    return Int(old)
end

# ORIGINAL: `open(2)` through Julia's `open`: the file as an `IOStream`, or the errno.
function _open_julia_file(
    path::String, op::Char, mode::Int
)::Union{IOStream, Int}
    existed = op != 'r' && (
        try
            ispath(path)
        catch
            false
        end
    )    # `ispath` throws on ENAMETOOLONG, ELOOP
    io = try
        if op == 'w'
            open(path; write=true, create=true, truncate=true)
        elseif op == 'a'
            open(path; write=true, create=true, append=true)
        elseif op == 'u'
            open(path; write=true, create=true, truncate=false)     # update: no truncation
        else
            open(path; read=true)
        end
    catch e
        e isa SystemError || rethrow()
        return Int(e.errnum)
    end
    if op != 'r' && !existed && mode != 0o666           # the mode of a file this call created
        try
            chmod(path, mode & ~_current_umask())
        catch e
            e isa Union{SystemError, Base.IOError} || rethrow()
        end
    end
    return io
end

# ORIGINAL: the lock loop of pl-stream.c `Sopen_file` (`fcntl(fd, wait ? F_SETLKW : F_SETLK, &buf)`) as a helper:
# `struct flock` is built by hand (Linux LP64: `short l_type`, `short l_whence`, `off_t l_start`, `off_t l_len`,
# `pid_t l_pid`: 32 bytes); `F_RDLCK` 0, `F_WRLCK` 1, `F_SETLK` 6, `F_SETLKW` 7, `SEEK_SET` 0. 0 or the errno; an
# `EINTR` retries as upstream does (`PL_handle_signals` has no signal to handle here).
"Lock the whole file of `io`, read (`lock == 1`) or write, waiting or not: 0 or the errno (pl-stream.c Sopen_file)."
function _fcntl_lock(io::IOStream, lock::Int, wait::Bool)::Int
    fdn = ccall(:jl_ios_fd, Clong, (Ptr{Cvoid},), io.ios) % Cint
    buf = zeros(UInt8, 32)
    buf[1] = lock == 1 ? 0x00 : 0x01                    # l_type: F_RDLCK, F_WRLCK (little endian short)
    cmd = wait ? Cint(7) : Cint(6)                      # F_SETLKW, F_SETLK
    while true
        rc = GC.@preserve buf ccall(
            :fcntl, Cint, (Cint, Cint, Ptr{UInt8}), fdn, cmd, pointer(buf)
        )
        rc == 0 && return 0
        e = Int(Base.Libc.errno())
        e == 4 || return e                              # EINTR: try again
    end
end

# PORT: pl-stream.c Sopen_file
# DIVERGES: returns `(stream, errno)` — the stream, or `nothing` and the errno that upstream leaves
# in `errno`; the file is Julia's (`open`, an `IOStream`), so a failure's errno is what Julia's
# `SystemError` carries; a new file gets `mode` less the umask by a `chmod` after the open; the
# advisory lock (`l`, `L`: upstream's FCNTL_LOCKS branch) is `_fcntl_lock` on the descriptor of the
# Julia file. `initenc` and `uatoms` are `Snew`'s (`ld.encoding`, `ld.unicode_atoms`). `how`: `r`, `w`, `a` or `u`, then `b` (binary), `r` (no position), `lr`/`lw`/`Lr`/`Lw`
# (a read or write lock; `L` fails instead of waiting), `m` and three octal digits (the mode of a new file).
"Open the file `path` as `how` says: the stream and 0, or `nothing` and the errno (pl-stream.c)."
function Sopen_file(
    path::String, how::String, initenc::IOENC = ENC_UTF8, uatoms::Sunicode_atoms_t = S_UATOMS_ACCEPT
)::Tuple{Union{Nothing, IOSTREAM}, Int}
    isempty(how) && return (nothing, EINVAL)
    op = how[1]
    flags = SIO_FILE | SIO_TEXT | SIO_RECORDPOS | SIO_FBUF
    enc = ENC_UNKNOWN
    mode = Int(0o666)
    lock = 0                                                # lnone, lread = 1, lwrite = 2
    wait = true
    i = 2
    while i <= lastindex(how)
        c = how[i]
        if c == 'b'                                         # binary
            flags &= ~SIO_TEXT
            enc = ENC_OCTET
        elseif c == 'r'                                     # no record
            flags &= ~SIO_RECORDPOS
        elseif c == 'L' || c == 'l'                         # lock r: read, w: write
            c == 'L' && (wait = false)
            i += 1
            if i <= lastindex(how) && how[i] == 'r'
                lock = 1
            elseif i <= lastindex(how) && how[i] == 'w'
                lock = 2
            else
                return (nothing, EINVAL)
            end
        elseif c == 'm'
            (i + 3 <= lastindex(how) && all(d -> '0' <= d <= '7', how[(i + 1):(i + 3)])) ||
                return (nothing, EINVAL)
            mode = parse(Int, how[(i + 1):(i + 3)]; base=8)
            i += 3
        else
            return (nothing, EINVAL)
        end
        i += 1
    end

    if op == 'w'
        flags |= SIO_OUTPUT
    elseif op == 'a'
        flags |= SIO_OUTPUT | SIO_APPEND
    elseif op == 'u'
        flags |= SIO_OUTPUT | SIO_UPDATE
    elseif op == 'r'
        flags |= SIO_INPUT
    else
        return (nothing, EINVAL)
    end

    io = _open_julia_file(path, op, mode)
    io isa Int && return (nothing, io)
    if lock != 0
        lerr = _fcntl_lock(io, lock, wait)
        if lerr != 0
            close(io)
            return (nothing, lerr)
        end
    end
    s = Snew(Sjulia_io(io, true), flags, Siofunctions, initenc, uatoms)
    enc != ENC_UNKNOWN && (s.encoding = enc)
    return (s, 0)
end

# PORT: pl-stream.c Sfdopen
# DIVERGES: returns `(stream, errno)` as `Sopen_file` does; the descriptor is the Julia IO's (`Base.fdio`, which owns it: the
# stream closes it, as upstream's `Sclose` of a file stream does); the check `fcntl(fd, F_GETFL) == -1` is a `stat` of the
# descriptor (EBADF for one that is not open); a text stream's encoding is `Snew`'s (UTF-8).
"A stream on the open file descriptor `fd`, `type` `r` or `w` and `b` for a binary stream: the stream and 0, or `nothing` and the errno (pl-stream.c)."
function Sfdopen(fd::Int, type::String)::Tuple{Union{Nothing, IOSTREAM}, Int}
    flags = SIO_FILE | SIO_RECORDPOS | SIO_FBUF
    fd < 0 && return (nothing, EINVAL)
    try
        stat(RawFD(fd))
    catch e
        e isa Base.IOError || rethrow()
        return (nothing, -Int(e.code))
    end
    c = isempty(type) ? '\0' : type[1]
    if c == 'r'
        flags |= SIO_INPUT
    elseif c == 'w'
        flags |= SIO_OUTPUT
    else
        return (nothing, EINVAL)
    end
    (length(type) < 2 || type[2] != 'b') && (flags |= SIO_TEXT)
    return (Snew(Sjulia_io(Base.fdio("<fd $fd>", fd, true), true), flags, Siofunctions), 0)
end
