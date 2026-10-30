# UPSTREAM: swipl-devel src/os/pl-file.c @ cbf4e1896275
# UPSTREAM: swipl-devel src/os/pl-file.h @ cbf4e1896275
# UPSTREAM: swipl-devel src/pl-global.h @ cbf4e1896275
# UPSTREAM: swipl-devel src/os/pl-stream.c @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# THE STREAM TABLE, the part the loader needs (R1f): the file name an open stream reads, which
# upstream keeps in the stream's context (`getStreamContext(s)->filename`) and the reader puts in a
# term's source location and a syntax error's `file(…)`. Since R1e's write/1 family (decision 2a,
# user 2026-10-07: the current output a Julia IO the host sets, stdout by default, with the aliases
# `user_output` and `user_error`): THE STANDARD STREAMS — `user_input`, `user_output`, `user_error`
# over the process's stdin, stdout and stderr (`initIO`), `current_input`/`current_output` naming
# them (no see/tell), the host's `set_standard_stream!` — and looking up an output stream by alias
# (`getOutputStream`), with upstream's errors, and a stream's error state (`streamStatus`).
#
# Since R2's S1: STREAM BLOBS, USER ALIASES, `open/3,4` and `close/1,2`. A stream Prolog knows has an
# entry in the database's stream table (`getStreamContext`); an alias is an entry of the alias table
# (`aliasStream`); `open/3,4` (`openStream`) unifies its third argument with the stream's first
# alias or, without one, with a STREAM BLOB (`unify_stream_ref`): an atom of the non-text blob type
# `stream` (`stream_blob`, the BLOB commit's interface: `lookupBlob` + `_blob_term!`), whose payload is
# a `stream_ref` (the stream's number in the table), written `<stream>(0x…)`; `close/1,2`
# (`pl_close`) closes a stream by blob or alias; closing frees the stream's table entry and aliases
# (`freeStream`, which upstream runs as the close hook). NOT PORTED: the rest of the stream table —
# the stream properties, input streams for read/1, `set_stream/2`, `stream_pair/3` (a pair blob), the
# current-stream predicates, `open_null_stream/1`, `see/tell`, `with_output_to/2` and the output
# redirection (O1); no locks (no threads), no atom/stream garbage collection (a blob is never
# freed: a closed stream's blob stays a blob, its stream gone from the table).

# PORT: pl-file.c fileNameStream
# DIVERGES: the name lives in the database's `stream_filenames` (src/pl-global.jl), where upstream
# keeps it in the stream's context; no lock (no threads).
"The name of the file `s` reads, or `nothing` (pl-file.c)."
fileNameStream(gd::PL_global_data{T}, s::IOSTREAM) where {T} =
    get(gd.stream_filenames, s, nothing)::Union{Nothing, T}

# PORT: pl-file.c setFileNameStream
# DIVERGES: as `fileNameStream`; `nothing` is upstream's NULL_ATOM — it, or `''`, forgets the
# stream's name (`setFileNameStream_unlocked`); no lock.
"Record that `s` reads the file named `name` (pl-file.c)."
function setFileNameStream(
    gd::PL_global_data{T}, s::IOSTREAM, name::Union{Nothing, T}
)::Bool where {T}
    if name === nothing || sym_text(name) == ""
        delete!(gd.stream_filenames, s)
    else
        gd.stream_filenames[s] = name
    end
    return true
end

# ── the standard streams (since R1e's write/1 family) ───────────────────────────────────────────

# PORT: pl-file.h SNO_USER_INPUT
"The index of `user_input` among the standard streams (pl-file.h)."
const SNO_USER_INPUT = 0
# PORT: pl-file.h SNO_USER_OUTPUT
"The index of `user_output` among the standard streams (pl-file.h)."
const SNO_USER_OUTPUT = 1
# PORT: pl-file.h SNO_USER_ERROR
"The index of `user_error` among the standard streams (pl-file.h)."
const SNO_USER_ERROR = 2
# PORT: pl-file.h SNO_CURRENT_INPUT
"The index of `current_input` among the standard streams (pl-file.h)."
const SNO_CURRENT_INPUT = 3
# PORT: pl-file.h SNO_CURRENT_OUTPUT
"The index of `current_output` among the standard streams (pl-file.h)."
const SNO_CURRENT_OUTPUT = 4
# PORT: pl-file.h SNO_PROTOCOL
"The index of `protocol` among the standard streams (pl-file.h)."
const SNO_PROTOCOL = 5

# PORT: pl-file.h ST_FALSE
"`stream_type_check` off (pl-file.h)."
const ST_FALSE = -1
# PORT: pl-file.h ST_LOOSE
"`stream_type_check` loose, the default: a text stream may be written as binary (pl-file.h)."
const ST_LOOSE = 0
# PORT: pl-file.h ST_TRUE
"`stream_type_check` strict (pl-file.h)."
const ST_TRUE = 1

# PORT: pl-file.c SH_ERRORS
"Stream lookup flag: raise an error on failure (pl-file.c)."
const SH_ERRORS = Int(0x01)
# PORT: pl-file.c SH_ALIAS
"Stream lookup flag: allow an alias (pl-file.c)."
const SH_ALIAS = Int(0x02)
# PORT: pl-file.c SH_UNLOCKED
"Stream lookup flag: do not lock the stream (pl-file.c)."
const SH_UNLOCKED = Int(0x04)
# PORT: pl-file.c SH_OUTPUT
"Stream lookup flag: an output stream is wanted (pl-file.c)."
const SH_OUTPUT = Int(0x08)
# PORT: pl-file.c SH_INPUT
"Stream lookup flag: an input stream is wanted (pl-file.c)."
const SH_INPUT = Int(0x10)

# PORT: pl-file.c S_DONTCARE
"Stream type wanted: any (pl-file.c `s_type`)."
const S_DONTCARE = 0
# PORT: pl-file.c S_TEXT
"Stream type wanted: a text stream (pl-file.c `s_type`)."
const S_TEXT = 1
# PORT: pl-file.c S_BINARY
"Stream type wanted: a binary stream (pl-file.c `s_type`)."
const S_BINARY = 2

# PORT: pl-global.h Suser_input
"The `user_input` stream, or `nothing` (pl-global.h)."
Suser_input(ld::PL_local_data) = ld.IO_streams[SNO_USER_INPUT + 1]
# PORT: pl-global.h Suser_output
"The `user_output` stream, or `nothing` (pl-global.h)."
Suser_output(ld::PL_local_data) = ld.IO_streams[SNO_USER_OUTPUT + 1]
# PORT: pl-global.h Suser_error
"The `user_error` stream, or `nothing` (pl-global.h)."
Suser_error(ld::PL_local_data) = ld.IO_streams[SNO_USER_ERROR + 1]
# PORT: pl-global.h Scurin
"The current input stream, or `nothing` (pl-global.h)."
Scurin(ld::PL_local_data) = ld.IO_streams[SNO_CURRENT_INPUT + 1]
# PORT: pl-global.h Scurout
"The current output stream, or `nothing` (pl-global.h)."
Scurout(ld::PL_local_data) = ld.IO_streams[SNO_CURRENT_OUTPUT + 1]

# PORT: pl-file.c standardStreams
# DIVERGES: the atoms' texts, a tuple (upstream: a NULL-terminated array of `atom_t`).
"The names of the standard streams, by `SNO_*` index (pl-file.c)."
const standardStreams = (
    :user_input, :user_output, :user_error, :current_input, :current_output, :protocol
)

# PORT: pl-file.c standardStreamIndexFromName
"The `SNO_*` index of the standard stream named `name`, or -1 (pl-file.c)."
function standardStreamIndexFromName(ld::PL_local_data{T}, name::T)::Int where {T}
    for (i, a) in enumerate(standardStreams)
        sym_key(mk_sym(T, a)) == sym_key(name) && return i - 1
    end
    return -1
end

# PORT: pl-file.c standardStreamIndexFromStream
"The `SNO_*` index of the standard stream `s` is, or -1 (pl-file.c)."
function standardStreamIndexFromStream(ld::PL_local_data, s::IOSTREAM)::Int
    for i in 0:SNO_PROTOCOL
        ld.IO_streams[i + 1] === s && return i
    end
    return -1
end

# A standard stream over `io` with `flags` (pl-stream.c `S__iob0`): `SIO_ISATTY` only on a terminal
# (pl-stream.c `SinitStreams`).
function _std_stream(
    io::Union{IOStream, IOBuffer, Base.TTY, Base.PipeEndpoint}, flags::UInt32
)::IOSTREAM
    io isa Base.TTY || (flags &= ~SIO_ISATTY)
    return Snew(Sjulia_io(io, false), flags, Siofunctions)
end

# PORT: pl-stream.c S__iob0 as _std_io
# DIVERGES: the process's Julia IO `io` (Base.stdin, stdout or stderr) when it is one the stream layer
# holds (`Sjulia_io`); any other (a runner's wrapper) gives way to the OS file descriptor `fd` itself
# (`fdio`, not owned): upstream's standard stream `n` is file descriptor `n` whatever it is
# (cbf4e189 pl-stream.c:4479-4492, `STDIO(n, f)`: `.handle = (void *)(n)`).
"The IO standard stream `fd` (0, 1 or 2) reads or writes: `io`, or the file descriptor `fd` (pl-stream.c)."
function _std_io(io::IO, fd::Int)::Union{IOStream, IOBuffer, Base.TTY, Base.PipeEndpoint}
    io isa Union{IOStream, IOBuffer, Base.TTY, Base.PipeEndpoint} && return io
    return fdio(fd, false)
end

# PORT: pl-file.c initIO
# DIVERGES: per local data, the FIRST TIME a standard stream is asked for (a new local data opens no
# stream; the host may replace them, `set_standard_stream!`), where upstream opens them at start-up:
# `Sinput`, `Soutput` and `Serror` (pl-stream.c `S__iob0`'s flags: line-buffered input and output,
# an unbuffered error stream) over Julia's stdin, stdout and stderr (`_std_io`); the three share `Sinput`'s
# position record, as upstream. No tty modes, no protocol stream (`Sprotocol` stays NULL), no stream
# contexts or alias table (the aliases are `standardStreams`).
"Open the standard streams of `ld` over the process's stdin, stdout and stderr (pl-file.c)."
function initIO(ld::PL_local_data)::Nothing
    sin = _std_stream(_std_io(Base.stdin, 0), SIO_STDIO | SIO_LBUF | SIO_INPUT | SIO_NOFEOF)
    sout = _std_stream(
        _std_io(Base.stdout, 1), SIO_STDIO | SIO_LBUF | SIO_OUTPUT | SIO_REPPLU
    )
    serr = _std_stream(
        _std_io(Base.stderr, 2), SIO_STDIO | SIO_NBUF | SIO_OUTPUT | SIO_REPPLU
    )
    sin.position = sin.posbuf                       # position logging
    sout.position = sin.posbuf
    serr.position = sin.posbuf

    ld.IO_streams[SNO_USER_INPUT + 1] = sin         # Suser_input  = Sinput
    ld.IO_streams[SNO_USER_OUTPUT + 1] = sout       # Suser_output = Soutput
    ld.IO_streams[SNO_USER_ERROR + 1] = serr        # Suser_error  = Serror
    ld.IO_streams[SNO_CURRENT_INPUT + 1] = sin      # Scurin       = Sinput
    ld.IO_streams[SNO_CURRENT_OUTPUT + 1] = sout    # Scurout      = Soutput
    ld.IO_streams[SNO_PROTOCOL + 1] = nothing       # Sprotocol    = NULL
    ld.IO_initialised = true
    return nothing
end

"Open `ld`'s standard streams unless they are open (see `initIO`)."
_initIO(ld::PL_local_data)::Nothing = (ld.IO_initialised || initIO(ld); nothing)

# ORIGINAL: decision 2a's host interface — upstream's embedding code replaces `Suser_output` and its
# kin through `_PL_streams()`.
"""
    set_standard_stream!(ld, which, io) -> IOSTREAM

Make the standard stream `which` (`SNO_USER_INPUT`, `SNO_USER_OUTPUT` or `SNO_USER_ERROR`) of `ld` a
stream over the Julia IO `io` (a file, a buffer, a terminal or a pipe), with the standard stream's
buffering; `current_input` or `current_output` follows when it named the one replaced. The old
stream is flushed, never closed (the host owns its IO).
"""
function set_standard_stream!(
    ld::PL_local_data, which::Int,
    io::Union{IOStream, IOBuffer, Base.TTY, Base.PipeEndpoint}
)::IOSTREAM
    @assert which in (SNO_USER_INPUT, SNO_USER_OUTPUT, SNO_USER_ERROR)
    _initIO(ld)
    flags = if which == SNO_USER_INPUT
        SIO_STDIO | SIO_LBUF | SIO_INPUT | SIO_NOFEOF
    elseif which == SNO_USER_OUTPUT
        SIO_STDIO | SIO_LBUF | SIO_OUTPUT | SIO_REPPLU
    else
        SIO_STDIO | SIO_NBUF | SIO_OUTPUT | SIO_REPPLU
    end
    s = _std_stream(io, flags)::IOSTREAM
    s.position = s.posbuf
    old = ld.IO_streams[which + 1]
    old === nothing || (old.flags & SIO_OUTPUT) == 0 || Sflush(old)
    ld.IO_streams[which + 1] = s
    cur = which == SNO_USER_INPUT ? SNO_CURRENT_INPUT : SNO_CURRENT_OUTPUT
    if which != SNO_USER_ERROR && ld.IO_streams[cur + 1] === old
        ld.IO_streams[cur + 1] = s
    end
    return s
end

# ── errors (pl-file.c) ──────────────────────────────────────────────────────────────────────────

# PORT: pl-file.c no_stream
# DIVERGES: the name is the atom's text (upstream: an `atom_t`), used when `t` is 0.
"Raise `existence_error(stream, T)` — `T` the term `t` holds, else `name` (pl-file.c); false."
function no_stream(ld::PL_local_data{T}, t::term_t, name::Symbol)::Bool where {T}
    t != 0 && return PL_error(ld, ERR_EXISTENCE, mk_sym(T, :stream), t)
    return symbol_no_stream(ld, mk_sym(T, name))
end

# PORT: pl-file.c not_a_stream
"Raise `domain_error(stream_or_alias, T)` (`stream` without `SH_ALIAS`) for term `t` (pl-file.c); false."
function not_a_stream(ld::PL_local_data{T}, t::term_t, flags::Int)::Bool where {T}
    PL_error(
        ld, ERR_DOMAIN, mk_sym(T, (flags & SH_ALIAS) != 0 ? :stream_or_alias : :stream), t
    )
    return false
end

# PORT: pl-file.c symbol_no_stream
"Raise `existence_error(stream, Symbol)` (pl-file.c); false."
function symbol_no_stream(ld::PL_local_data{T}, symbol::T)::Bool where {T}
    t = PL_new_term_ref(ld)
    setSlotValue!(ld, t + 1, symbol)                        # PL_put_atom(t, symbol)
    return no_stream(ld, t, :stream)
end

# PORT: pl-file.c symbol_stream_wrong_mode
"Raise `permission_error(Action, stream, Symbol)`, 'requested stream has wrong mode' (pl-file.c); false."
function symbol_stream_wrong_mode(
    ld::PL_local_data{T}, symbol::T, action::Symbol
)::Bool where {T}
    t = PL_new_term_ref(ld)
    setSlotValue!(ld, t + 1, symbol)                        # PL_put_atom(t, symbol)
    return PL_error(
        ld, "", 0, "requested stream has wrong mode", ERR_PERMISSION, mk_sym(T, action),
        mk_sym(T, :stream), t
    )
end

# ── handles (pl-file.c) ─────────────────────────────────────────────────────────────────────────

# PORT: pl-file.c check_stream_mode
"Whether `s` has the mode `flags` asks for (`SH_INPUT`, `SH_OUTPUT`); if not, the error (pl-file.c)."
function check_stream_mode(
    ld::PL_local_data{T}, a::T, s::IOSTREAM, flags::Int
)::Bool where {T}
    action = if (flags & (SH_INPUT | SH_OUTPUT)) == SH_INPUT && (s.flags & SIO_INPUT) == 0
        :read
    elseif (flags & (SH_INPUT | SH_OUTPUT)) == SH_OUTPUT && (s.flags & SIO_OUTPUT) == 0
        :write
    else
        :none
    end

    if action !== :none
        (flags & SH_ERRORS) != 0 && return symbol_stream_wrong_mode(ld, a, action)
        return false
    end

    return true
end

# PORT: pl-file.c get_stream_handle
# DIVERGES: a stream blob's payload names the stream by its number in the database's stream table (see
# the file's header); a blob of a stream closed meanwhile is no stream (`existence_error`), its entry
# being gone from the table (upstream: `s->erased`). A pair (both `read` and `write`) is NOT PORTED
# (`stream_pair/3`). The alias table is the standard streams' names and the user aliases; returns the
# stream or `nothing`; no locks, so `SH_UNLOCKED` and `SH_TRYLOCK` are all one. NOT PORTED: the
# standard stream restored when its stream was closed (`restoreStandardStream` — the closers keep
# the standard streams open, see `closeStream`). A standard name whose stream is NULL is
# `existence_error(stream, Name)`: upstream's `goto noent` since its fix cd76c1a
# (docs/upstream_reports.md #13), and what the kernel did before it.
"The stream the blob or atom `a` names, as `flags` (`SH_*`) ask, or `nothing` with the error raised (pl-file.c)."
function get_stream_handle(
    ld::PL_local_data{T}, a::T, flags::Int
)::Union{Nothing, IOSTREAM} where {T}
    gd = _query_gd(ld)
    ref = _stream_ref_of(ld, a)
    if ref !== nothing                              # type == &stream_blob
        (ref.read != 0 && ref.write != 0) && throw(
            NotPortedError{T}(a, "a stream pair", "stream_pair/3 (not ported)")
        )
        s = _stream_of(gd, ref.read != 0 ? ref.read : ref.write)
        if s === nothing || s.erased                # if ( s->erased ) goto noent
            (flags & SH_ERRORS) != 0 && symbol_no_stream(ld, a)
            return nothing
        end

        check_stream_mode(ld, a, s, flags) || return nothing
        s.magic == SIO_MAGIC && return s            # getStream(s)
        symbol_no_stream(ld, a)
        return nothing
    end

    if kind(a) === SYM
        n = standardStreamIndexFromName(ld, a)      # lookupHTableWP(streamAliases, a)
        if n >= 0
            stream = ld.IO_streams[n + 1]           # LD->IO.streams[n]
            if stream !== nothing
                check_stream_mode(ld, a, stream, flags) || return nothing
                return stream
            end
        else
            stream = get(gd.stream_aliases, sym_key(a), nothing)
            if stream !== nothing && stream.magic == SIO_MAGIC
                check_stream_mode(ld, a, stream, flags) || return nothing
                return stream
            end
        end
    end

    (flags & SH_ERRORS) != 0 && symbol_no_stream(ld, a)     # noent:
    return nothing
end

# PORT: pl-file.c checkStreamType
# DIVERGES: returns the error's type (`binary_stream`, `text_stream`), or `nothing` when `s` is of
# the type wanted, where upstream returns a Boolean and writes the type through `error`.
"Whether `s` is a stream of the type `text` asks for: `nothing`, or the error's type (pl-file.c)."
function checkStreamType(ld::PL_local_data, text::Int, s::IOSTREAM)::Union{Nothing, Symbol}
    (text == S_DONTCARE || ld.IO_stream_type_check == ST_FALSE) && return nothing   # no checking

    text == S_TEXT && (s.flags & SIO_TEXT) != 0 && return nothing                     # ok?
    text == S_BINARY && (s.flags & SIO_TEXT) == 0 && return nothing
    if ld.IO_stream_type_check == ST_LOOSE                                            # no
        text == S_TEXT && return nothing
        (s.encoding == ENC_ISO_LATIN_1 || s.encoding == ENC_OCTET) && return nothing
    end

    return text == S_TEXT ? :binary_stream : :text_stream
end

# PORT: pl-file.c getOutputStream
# DIVERGES: returns the stream or `nothing`; no locks (`getStream`, `releaseStream`). The standard
# streams are opened the first time one is asked for (`initIO`).
"""
The output stream term reference `t` names — 0: the current output; `user`: `user_output`; else an
alias — of the type `text` asks for, or `nothing` with upstream's error raised (pl-file.c).
"""
function getOutputStream(
    ld::PL_local_data{T}, t::term_t, text::Int
)::Union{Nothing, IOSTREAM} where {T}
    _initIO(ld)
    if t == 0
        s = Scurout(ld)
        if s === nothing
            no_stream(ld, t, :current_output)
            return nothing
        end
    else
        a = PL_get_atom(ld, t)
        if a === nothing
            not_a_stream(ld, t, SH_ALIAS)
            return nothing
        end

        if isTextAtom(a) && sym_key(a) == sym_key(mk_sym(T, :user))
            s = Suser_output(ld)
            if s === nothing
                no_stream(ld, t, :user)
                return nothing
            end
        else
            s = get_stream_handle(ld, a, SH_ERRORS | SH_ALIAS | SH_OUTPUT)
            s === nothing && return nothing
        end
    end

    tp = if (s.flags & SIO_OUTPUT) == 0                 # ok:
        :stream
    else
        checkStreamType(ld, text, s)
    end
    tp === nothing && return s

    if t == 0
        t = PL_new_term_ref(ld)
        setSlotValue!(ld, t + 1, mk_sym(T, :current_output))    # PL_put_atom(t, ATOM_current_output)
    end
    PL_error(ld, "", 0, "", ERR_PERMISSION, mk_sym(T, :output), mk_sym(T, tp), t)

    return nothing
end

# PORT: pl-file.c getTextOutputStream
"The text output stream term reference `t` names (0: the current output), or `nothing` (pl-file.c)."
getTextOutputStream(ld::PL_local_data{T}, t::term_t) where {T} =
    getOutputStream(ld, t, S_TEXT)

# PORT: pl-file.c getInputStream
# DIVERGES: returns the stream or `nothing`; no locks (`getStream`, `releaseStream`). The standard
# streams are opened the first time one is asked for (`initIO`). An alias is a standard stream's
# name (`get_stream_handle`: no stream blobs, no user aliases — R2's stream table), as
# `getOutputStream`'s.
"""
The input stream term reference `t` names — 0: the current input; `user`: `user_input`; else an
alias — of the type `text` asks for, or `nothing` with upstream's error raised (pl-file.c).
"""
function getInputStream(
    ld::PL_local_data{T}, t::term_t, text::Int
)::Union{Nothing, IOSTREAM} where {T}
    _initIO(ld)
    if t == 0
        s = Scurin(ld)
        if s === nothing
            no_stream(ld, t, :current_input)
            return nothing
        end
    else
        a = PL_get_atom(ld, t)
        if a === nothing
            not_a_stream(ld, t, SH_ALIAS)
            return nothing
        end

        if isTextAtom(a) && sym_key(a) == sym_key(mk_sym(T, :user))
            s = Suser_input(ld)
            if s === nothing
                no_stream(ld, t, :user)
                return nothing
            end
        else
            s = get_stream_handle(ld, a, SH_ERRORS | SH_ALIAS | SH_INPUT)
            s === nothing && return nothing
        end
    end

    tp = if (s.flags & SIO_INPUT) == 0                  # ok:
        :stream
    else
        checkStreamType(ld, text, s)
    end
    tp === nothing && return s

    if t == 0
        t = PL_new_term_ref(ld)
        setSlotValue!(ld, t + 1, mk_sym(T, :current_input))     # PL_put_atom(t, ATOM_current_input)
    end
    PL_error(ld, "", 0, "", ERR_PERMISSION, mk_sym(T, :input), mk_sym(T, tp), t)

    return nothing
end

# PORT: pl-file.c getTextInputStream
"The text input stream term reference `t` names (0: the current input), or `nothing` (pl-file.c)."
getTextInputStream(ld::PL_local_data{T}, t::term_t) where {T} =
    getInputStream(ld, t, S_TEXT)

# PORT: pl-file.c PL_unify_stream_or_alias
# DIVERGES: no lock around the alias list; `unify_stream_ref` makes the blob (see the file's header).
"Unify term reference `t` with the alias of the stream `s`, else with its blob (pl-file.c)."
function PL_unify_stream_or_alias(
    ld::PL_local_data{T}, t::term_t, s::IOSTREAM
)::Bool where {T}
    i = standardStreamIndexFromStream(ld, s)
    (i >= 0 && i < 3) && return PL_unify_atom(ld, t, mk_sym(T, standardStreams[i + 1]))

    gd = _query_gd(ld)
    names = s.context != 0 ? get(gd.stream_alias_names, s.context, nothing) : nothing
    if names !== nothing && !isempty(names)         # (ctx=getExistingStreamContext(s)) && ctx->alias_head
        return PL_unify_atom(ld, t, names[1])
    end
    return unify_stream_ref(ld, t, s)
end

# PORT: pl-file.c PL_unify_stream
"Unify term reference `t` with the blob of the stream `s`, which Prolog then knows (pl-file.c)."
function PL_unify_stream(ld::PL_local_data, t::term_t, s::IOSTREAM)::Bool
    getStreamContext(_query_gd(ld), s)              # get stream known to Prolog
    return unify_stream_ref(ld, t, s)
end

# PORT: pl-file.c reportStreamError
# DIVERGES: no halt state, no console streams (Windows), no recorded exception (`s->exception`), no
# timeouts (`SIO_TIMEOUT`); the message of an error without one is "I/O error", where upstream
# reads `errno` (`MSG_ERRNO`) — a Julia IO's failure carries none.
"Raise the error, or print the warning, that the error state of `s` records (pl-file.c)."
function reportStreamError(ld::PL_local_data{T}, s::IOSTREAM)::Bool where {T}
    if (s.flags & (SIO_FERR | SIO_WARN)) != 0
        stream = PL_new_term_ref(ld)
        PL_unify_stream_or_alias(ld, stream, s) || return false

        if (s.flags & SIO_FERR) != 0
            ld.exception_term != 0 && return false

            if (s.flags & SIO_INPUT) != 0
                if Sfpasteof(s) != 0
                    return PL_error(
                        ld, "", 0, "", ERR_PERMISSION, mk_sym(T, :input),
                        mk_sym(T, :past_end_of_stream), stream
                    )
                end
                op = :read
            else
                op = :write
            end

            m = s.message
            msg = m === nothing ? "I/O error" : m
            PL_error(ld, "", 0, msg, ERR_STREAM_OP, mk_sym(T, op), stream)
            Sclearerr(s)

            return false
        else
            rc = printMessage(                      # PL_FUNCTOR_CHARS, "io_warning", 2,
                ld, :warning,                       #   PL_TERM, stream, PL_CHARS, s->message
                _message_term(
                    ld, :io_warning, stream,
                    _err_atom(ld, mk_sym(T, Symbol(something(s.message, ""))))
                )
            )
            Sseterr(s, UInt32(0), nothing)

            return rc
        end
    end

    return true
end

# PORT: pl-file.c streamStatus
# DIVERGES: no locks (`releaseStream`).
"Whether `s` is free of errors; an error recorded on it is raised (pl-file.c)."
function streamStatus(ld::PL_local_data, s::IOSTREAM)::Bool
    (s.flags & (SIO_FERR | SIO_WARN)) != 0 && return reportStreamError(ld, s)
    return true
end

# ── stream blobs (pl-file.c), since R2's S1 ─────────────────────────────────────────────────────

# PORT: pl-file.c stream_ref
# DIVERGES: `read` and `write` are the NUMBERS of the streams in the database's stream table
# (`getStreamContext`; 0 for NULL), where upstream holds the `IOSTREAM *`s: a Julia stream is no
# pointer. A pair (both set) is NOT PORTED.
"The data of a stream blob (pl-file.c `stream_ref`): the streams it reads and writes, by table number (0: none)."
struct stream_ref
    read::Int
    write::Int
end

# PORT: pl-file.c stream_blob
# DIVERGES: no `release`, `compare` or `write` hooks (no atom GC; the blob's order and written form are
# the term interface's, D-0200: `<stream>(0x…)`).
"The blob type of a stream (pl-file.c `stream_blob`): unique by payload, non-text, named `stream`."
const stream_blob = PL_blob_t(PL_BLOB_UNIQUE, "stream")

# ORIGINAL: the payload bytes of a `stream_ref` (upstream stores the struct's memory).
"The 16 bytes of `ref`: `read` then `write`, little-endian."
_stream_ref_bytes(ref::stream_ref)::Vector{UInt8} =
    collect(reinterpret(UInt8, Int64[ref.read, ref.write]))

# ORIGINAL: the stream blob of `ref` as a term of type `T`: `PL_unify_blob`'s `lookupBlob` (unique by
# payload: one atom per `ref`) and the blob term of its atom word (`_blob_term!`).
"The blob term of type `T` that is the stream blob of `ref`."
function _stream_blob_term(ld::PL_local_data{T}, ref::stream_ref)::T where {T}
    bytes = _stream_ref_bytes(ref)
    w, _ = lookupBlob(ld.atoms, bytes, length(bytes), stream_blob)
    return _blob_term!(ld.atoms, ld.atom_symbols, T, w)
end

# ORIGINAL: `PL_blob_data(a, NULL, &type)` and `type == &stream_blob`: the `stream_ref` the atom `a` holds,
# or `nothing` when `a` is no stream blob.
"The `stream_ref` of the stream blob `a`, or `nothing` (pl-file.c: `type == &stream_blob`)."
function _stream_ref_of(ld::PL_local_data{T}, a::T)::Union{Nothing, stream_ref} where {T}
    is_blob(a) || return nothing
    at = atomValue(ld.atoms, blob_handle(a))
    at.type === stream_blob || return nothing
    v = reinterpret(Int64, at.name[1:16])
    return stream_ref(Int(v[1]), Int(v[2]))
end

# ORIGINAL: the stream numbered `serial` in the table, or `nothing` (closed, or no such stream).
"The stream the table's entry `serial` holds, or `nothing`."
function _stream_of(gd::PL_global_data, serial::Int)::Union{Nothing, IOSTREAM}
    return 1 <= serial <= length(gd.stream_table) ? gd.stream_table[serial] : nothing
end

# PORT: pl-file.c getStreamContext
# DIVERGES: the context is the stream's entry in the database's table (`PL_global_data.stream_table`;
# `IOSTREAM.context` its index), where upstream allocates a `stream_context` (aliases, file name,
# flags) and keeps the table `streamContext`; the aliases are `stream_alias_names`, the file name
# `stream_filenames` (src/os/pl-file.jl `fileNameStream`).
"Make the stream `s` known to Prolog: its number in the table (pl-file.c)."
function getStreamContext(gd::PL_global_data, s::IOSTREAM)::Int
    if s.context == 0
        push!(gd.stream_table, s)
        s.context = length(gd.stream_table)         # addNewHTablePP(streamContext, s, ctx)
    end
    return s.context
end

# PORT: pl-file.c aliasStream
# DIVERGES: the alias table is keyed by the atom's `sym_key`, its names by the stream's context;
# no lock.
"Make `name` an alias of `s`, taking it from the stream that has it (pl-file.c)."
function aliasStream(gd::PL_global_data{T}, s::IOSTREAM, name::T)::Nothing where {T}
    sp = get(gd.stream_aliases, sym_key(name), nothing)
    sp === nothing || unaliasStream(gd, sp, name)   # ensure name is free (error?)

    ctx = getStreamContext(gd, s)
    gd.stream_aliases[sym_key(name)] = s            # addNewHTableWP(streamAliases, name, s)
    Sacquire(s)
    push!(get!(Vector{T}, gd.stream_alias_names, ctx), name)
    return nothing
end

# PORT: pl-file.c unaliasStream
# DIVERGES: as `aliasStream`; `nothing` for upstream's NULL_ATOM (all the aliases of `s`).
"Remove the alias `name` of `s`, else all its aliases (pl-file.c)."
function unaliasStream(
    gd::PL_global_data{T}, s::IOSTREAM, name::Union{Nothing, T}
)::Nothing where {T}
    names = s.context != 0 ? get(gd.stream_alias_names, s.context, nothing) : nothing
    if name !== nothing
        key = sym_key(name)
        if haskey(gd.stream_aliases, key)
            delete!(gd.stream_aliases, key)
            if names !== nothing
                i = findfirst(a -> sym_key(a) == key, names)
                i === nothing || deleteat!(names, i)
            end
            Srelease(s)
        end
    elseif names !== nothing                        # delete them all
        for a in names
            if haskey(gd.stream_aliases, sym_key(a))
                delete!(gd.stream_aliases, sym_key(a))
                Srelease(s)
            end
        end
        empty!(names)
    end
    return nothing
end

# PORT: pl-file.c restoreStandardStream
# DIVERGES: upstream puts back the process's own `Sinput`, `Soutput` or `Serror`; the kernel has no
# such permanent stream, so a fresh standard stream over stdin, stdout or stderr is made.
"Put a standard stream back as standard stream number `i` after its stream was closed (pl-file.c)."
function restoreStandardStream(ld::PL_local_data, i::Int)::Union{Nothing, IOSTREAM}
    s = if i == SNO_USER_INPUT || i == SNO_CURRENT_INPUT
        _std_stream(_std_io(Base.stdin, 0), SIO_STDIO | SIO_LBUF | SIO_INPUT | SIO_NOFEOF)
    elseif i == SNO_USER_OUTPUT || i == SNO_CURRENT_OUTPUT
        _std_stream(_std_io(Base.stdout, 1), SIO_STDIO | SIO_LBUF | SIO_OUTPUT | SIO_REPPLU)
    elseif i == SNO_USER_ERROR
        _std_stream(_std_io(Base.stderr, 2), SIO_STDIO | SIO_NBUF | SIO_OUTPUT | SIO_REPPLU)
    else
        nothing
    end
    s !== nothing && (s.position = s.posbuf)
    ld.IO_streams[i + 1] = s
    return s
end

# PORT: pl-file.c freeStream
# DIVERGES: upstream registers it as the stream layer's close hook (`Sclosehook`), run by every
# `Sclose()`; the kernel's closers call it right after (`closeStream`, `do_close`, `openStream`'s
# failures) — the only closers of a stream that has a context. The source-file name (`source_file_name`)
# and the lock are NOT PORTED.
"Forget the stream `s`: its aliases, its entry in the table and its file name; a standard stream that was `s` is put back (pl-file.c)."
function freeStream(ld::PL_local_data, s::IOSTREAM)::Nothing
    gd = _query_gd(ld)
    unaliasStream(gd, s, nothing)

    if s.context != 0
        gd.stream_table[s.context] = nothing        # deleteHTablePP(streamContext, s)
        delete!(gd.stream_alias_names, s.context)
    end
    delete!(gd.stream_filenames, s)                 # ctx->filename

    for i in 0:SNO_PROTOCOL                         # if we are a standard stream
        if ld.IO_streams[i + 1] === s               # reassociate with standard I/O
            if i == SNO_CURRENT_INPUT
                ld.IO_streams[i + 1] = Suser_input(ld)
            elseif i == SNO_CURRENT_OUTPUT
                ld.IO_streams[i + 1] = Suser_output(ld)
            elseif i == SNO_PROTOCOL
                ld.IO_streams[i + 1] = nothing
            else
                restoreStandardStream(ld, i)
            end
        end
    end
    return nothing
end

# PORT: pl-file.c getStream
# DIVERGES: no lock.
"The stream `s` if it is open, else `nothing` (pl-file.c)."
getStream(s::IOSTREAM)::Union{Nothing, IOSTREAM} = s.magic == SIO_MAGIC ? s : nothing

# PORT: pl-file.c unify_stream_ref
"Unify term reference `t` with the blob of the stream `s` (pl-file.c)."
function unify_stream_ref(ld::PL_local_data{T}, t::term_t, s::IOSTREAM)::Bool where {T}
    ctx = getStreamContext(_query_gd(ld), s)
    ref = (s.flags & SIO_INPUT) != 0 ? stream_ref(ctx, 0) : stream_ref(0, ctx)
    rval = PL_unify_atom(ld, t, _stream_blob_term(ld, ref))      # PL_unify_blob(t, &ref, …)

    if !rval && !PL_is_variable(ld, t)
        return PL_error(ld, "", 0, "stream-argument", ERR_UNINSTANTIATION, 0, t)
    end
    return rval
end

# ── open/3,4 (pl-file.c) ────────────────────────────────────────────────────────────────────────

# ORIGINAL: whether the atom `a` is the text atom `name` (by its text: no term is built, so no term type
# is taken from the argument).
_sym_is(a, name::Symbol)::Bool =
    kind(a) === SYM && !is_reserved_symbol(a) && !is_blob(a) && Symbol(sym_text(a)) === name

# PORT: pl-file.c encoding_names
# DIVERGES: the names as symbols, in upstream's order, the aliases last; `PL_atom_to_encoding` reads
# the table (`PL_encoding_to_atom` is NOT PORTED: no caller).
const encoding_names = (
    (:octet, ENC_OCTET), (:ascii, ENC_ASCII), (:iso_latin_1, ENC_ISO_LATIN_1),
    (:text, ENC_ANSI), (:utf8, ENC_UTF8), (:utf16be, ENC_UTF16BE),
    (:utf16le, ENC_UTF16LE), (:wchar_t, ENC_WCHAR),
    (Symbol("ISO-8859-1"), ENC_ISO_LATIN_1), (Symbol("UTF-8"), ENC_UTF8),
    (:unicode_be, ENC_UTF16BE), (:unicode_le, ENC_UTF16LE),
    (Symbol("UTF-16BE"), ENC_UTF16BE), (Symbol("UTF-16LE"), ENC_UTF16LE)
)

# PORT: pl-file.c PL_atom_to_encoding
"The encoding the atom `a` names, or `ENC_UNKNOWN` (pl-file.c)."
function PL_atom_to_encoding(a::T)::IOENC where {T}
    (kind(a) === SYM && !is_reserved_symbol(a) && !is_blob(a)) || return ENC_UNKNOWN
    name = Symbol(sym_text(a))
    for (n, enc) in encoding_names
        n === name && return enc
    end
    return ENC_UNKNOWN
end

# PORT: pl-file.c bad_encoding
"Raise `domain_error(encoding, Name)` with the message `msg` (empty: none); false (pl-file.c)."
function bad_encoding(ld::PL_local_data{T}, msg::String, name::T)::Bool where {T}
    t = PL_new_term_ref(ld)
    PL_put_atom(ld, t, name)
    return PL_error(ld, "", 0, msg, ERR_DOMAIN, mk_sym(T, :encoding), t)
end

# PORT: pl-file.c stream_encoding_options
# DIVERGES: returns `(encoding, bom)` or `nothing` with the error raised, where upstream writes them
# through `enc` and `bom`; `bom` is -1 (not given), 0 or 1; the `encoding` flag (`LD->encoding`) is
# UTF-8 (the flag table is F1's).
"The encoding and the BOM policy an `open/4` with these `type` and `encoding` options gives (pl-file.c)."
function stream_encoding_options(
    ld::PL_local_data{T}, type::T, encoding::Union{Nothing, T}, bom::Int
)::Union{Nothing, Tuple{IOENC, Int}} where {T}
    if encoding !== nothing
        enc = PL_atom_to_encoding(encoding)
        if enc == ENC_UNKNOWN
            bad_encoding(ld, "", encoding)
            return nothing
        end
        if _sym_is(type, :binary) && enc != ENC_OCTET
            bad_encoding(ld, "type(binary) implies encoding(octet)", encoding)
            return nothing
        end
        if enc == ENC_OCTET || enc == ENC_ASCII || enc == ENC_ISO_LATIN_1 ||
            enc == ENC_WCHAR
            bom = 0         # explicitly specified: do not switch to Unicode
        end
        return (enc, bom)
    elseif _sym_is(type, :binary)
        return (ENC_OCTET, 0)
    elseif _sym_is(type, :text)
        return (ENC_UTF8, bom)                      # LD->encoding
    end
    ex = PL_new_term_ref(ld)
    PL_cons_functor(ld, ex, _err_functor(ld, :type, 1), _err_atom(ld, type))
    PL_domain_error(ld, "stream_option", ex)
    return nothing
end

# PORT: pl-file.c set_eof_action
"Set the end-of-file action of `s` from the atom `action`, else raise `domain_error(eof_action, A)` (pl-file.c)."
function set_eof_action(ld::PL_local_data{T}, s::IOSTREAM, action::T)::Bool where {T}
    if _sym_is(action, :eof_code)
        s.flags &= ~(SIO_NOFEOF | SIO_FEOF2ERR)
    elseif _sym_is(action, :reset)
        s.flags &= ~SIO_FEOF2ERR
        s.flags |= SIO_NOFEOF
    elseif _sym_is(action, :error)
        s.flags &= ~SIO_NOFEOF
        s.flags |= SIO_FEOF2ERR
    else
        t = PL_new_term_ref(ld)
        PL_put_atom(ld, t, action)
        return PL_domain_error(ld, "eof_action", t)
    end
    return true
end

# PORT: pl-file.c set_buffering
"Set the buffering of `s` from the atom `b`, else raise `domain_error(buffer, B)` (pl-file.c)."
function set_buffering(ld::PL_local_data{T}, s::IOSTREAM, b::T)::Bool where {T}
    abuf = SIO_FBUF | SIO_LBUF | SIO_NBUF                   # SIO_ABUF
    if _sym_is(b, :full)
        s.flags &= ~abuf
        s.flags |= SIO_FBUF
    elseif _sym_is(b, :line)
        s.flags &= ~abuf
        s.flags |= SIO_LBUF
    elseif _sym_is(b, Symbol("false"))       # (`:false` is the Bool)
        Sflush(s)
        s.flags &= ~abuf
        s.flags |= SIO_NBUF
    else
        t = PL_new_term_ref(ld)
        PL_put_atom(ld, t, b)
        return PL_domain_error(ld, "buffer", t)
    end
    return true
end

# PORT: pl-file.c open4_options
# DIVERGES: `locale` (`O_LOCALE`) is listed so that a locale is REFUSED (`NotPortedError`), not ignored.
const open4_options = (
    PL_option_t(:type, OPT_ATOM),
    PL_option_t(:reposition, OPT_BOOL),
    PL_option_t(:alias, OPT_ATOM),
    PL_option_t(:eof_action, OPT_ATOM),
    PL_option_t(:close_on_abort, OPT_BOOL),
    PL_option_t(:buffer, OPT_ATOM),
    PL_option_t(:lock, OPT_ATOM),
    PL_option_t(:wait, OPT_BOOL),
    PL_option_t(:encoding, OPT_ATOM),
    PL_option_t(:newline, OPT_ATOM),
    PL_option_t(:bom, OPT_BOOL),
    PL_option_t(:create, OPT_TERM),
    PL_option_t(:locale, OPT_TERM),
    PL_option_t(:unicode_atoms, OPT_ATOM)
)

# ORIGINAL: an option value that is an atom, else `nothing`.
function _opt_atom(::Type{T}, v)::Union{Nothing, T} where {T}
    return v isa T ? v : nothing
end

# ORIGINAL (BP2): pl-file.c `newline_domain_error`, a function upstream fix cd67bb35e added to the pin cbf4e189 (a
# named backport): the culprit of the domain error is a term reference holding the atom.
"Raise `domain_error(newline, Val)` with the message `msg` (empty: none) — the culprit a term reference holding the atom; false (pl-file.c)."
function newline_domain_error(ld::PL_local_data{T}, val::T, msg::String)::Bool where {T}
    t = PL_new_term_ref(ld)
    PL_put_atom(ld, t, val)
    return PL_error(ld, "", 0, msg, ERR_DOMAIN, mk_sym(T, :newline), t)
end

# PORT: pl-file.c atom_to_newline_mode
# The pin cbf4e189 plus upstream fix cd67bb35e (BP2, a named backport): the culprit is a term reference.
# DIVERGES: returns the mode (`SIO_NL_POSIX`, `SIO_NL_DOS`, `SIO_NL_DETECT`) or `nothing` with the error
# raised, where upstream writes `*mode` and returns a bool.
"The newline mode the atom `val` names for a stream with the flags `flags` (`SIO_INPUT` or `SIO_OUTPUT`), or `nothing` after raising the error (pl-file.c)."
function atom_to_newline_mode(
    ld::PL_local_data{T}, val::T, flags::UInt32
)::Union{Nothing, Int} where {T}
    if _sym_is(val, :posix)
        return SIO_NL_POSIX
    elseif _sym_is(val, :dos)
        return SIO_NL_DOS
    elseif _sym_is(val, :detect)
        if (flags & SIO_INPUT) == 0
            newline_domain_error(ld, val, "detect only allowed for input streams")
            return nothing
        end
        return SIO_NL_DETECT
    end
    newline_domain_error(ld, val, "")
    return nothing
end

# PORT: pl-file.c openStream
# DIVERGES: returns the stream, or `nothing` with the error raised; the file is opened by Julia
# (`Sopen_file`), a failure's error from its errno (`ERR_FILE_OPERATION`). NOT PORTED, each raising
# `NotPortedError` BEFORE a file is opened: `pipe(Command)` files (`Sopen_pipe`), IRIs (`iri_hook`),
# the `lock` option (no `flock`), the `locale` option (`PL_locale`), the `unicode_atoms` option
# (`atom_to_unicode_atoms_ex`, F1's) and the encodings the stream layer refuses (ANSI, UTF-16, wchar_t).
# `locale`'s default is the `encoding` flag's (`LD->encoding`): UTF-8.
"Open the file `file` as `mode` and `options` say (pl-file.c); the stream, or `nothing` after raising the error."
function openStream(
    ld::PL_local_data{T}, file::term_t, mode::term_t, options::term_t
)::Union{Nothing, IOSTREAM} where {T}
    gd = _query_gd(ld)
    _initIO(ld)
    type = mk_sym(T, :text)
    reposition = true
    alias = nothing
    eof_action = mk_sym(T, :eof_code)
    buffer = mk_sym(T, :full)
    lock = mk_sym(T, :none)
    newline = nothing
    encoding = nothing
    close_on_abort = true
    bom = -1
    create = 0

    if options != 0
        vals = PL_scan_options(ld, options, 0, "stream_option", open4_options)
        vals === nothing && return nothing
        v = _opt_atom(T, vals[1])
        v === nothing || (type = v)
        b2 = vals[2]
        b2 isa Bool && (reposition = b2)
        alias = _opt_atom(T, vals[3])
        v = _opt_atom(T, vals[4])
        v === nothing || (eof_action = v)
        b5 = vals[5]
        b5 isa Bool && (close_on_abort = b5)
        v = _opt_atom(T, vals[6])
        v === nothing || (buffer = v)
        v = _opt_atom(T, vals[7])
        v === nothing || (lock = v)
        encoding = _opt_atom(T, vals[9])
        newline = _opt_atom(T, vals[10])
        b11 = vals[11]
        b11 isa Bool && (bom = b11 ? 1 : 0)
        i12 = vals[12]
        i12 isa Int && (create = i12)
        if vals[13] !== nothing
            throw(NotPortedError{T}(type, "open/4's locale(Locale) option", "PL_locale"))
        end
        if vals[14] !== nothing
            throw(
                NotPortedError{T}(
                    type, "open/4's unicode_atoms(Mode) option", "F1 (the flags)"
                )
            )
        end
    end

    mname = PL_get_atom_ex(ld, mode)                            # MODE
    mname === nothing && return nothing
    how = Char[]
    if _sym_is(mname, :write)
        push!(how, 'w')
    elseif _sym_is(mname, :append)
        push!(how, 'a')
    elseif _sym_is(mname, :update)
        push!(how, 'u')
    elseif _sym_is(mname, :read)
        push!(how, 'r')
    else
        PL_error(ld, ERR_DOMAIN, mk_sym(T, :io_mode), mode)
        return nothing
    end
    if create != 0
        tail = PL_copy_term_ref(ld, create)
        head = PL_new_term_ref(ld)
        cmode = 0
        n = 0
        while PL_get_list(ld, tail, head, tail)
            a = PL_get_atom_ex(ld, head)
            a === nothing && return nothing
            if _sym_is(a, :read)
                cmode |= 0o444
            elseif _sym_is(a, :write)
                cmode |= 0o666
            elseif _sym_is(a, :execute)
                cmode |= 0o111
            elseif _sym_is(a, :default)
                cmode |= 0o666
            elseif _sym_is(a, :all)
                cmode |= 0o777
            end

            n += 1
            if n == 10 && PL_skip_list(ld, tail)[1] != PL_LIST
                PL_error(ld, ERR_TYPE, mk_sym(T, :list), create)
                return nothing
            end
        end
        PL_get_nil_ex(ld, tail) || return nothing
        push!(how, 'm')
        push!(how, Char('0' + ((cmode >> 6) & 7)))
        push!(how, Char('0' + ((cmode >> 3) & 7)))
        push!(how, Char('0' + (cmode & 7)))
    end

    ebom = stream_encoding_options(ld, type, encoding, bom)
    ebom === nothing && return nothing
    enc, bom = ebom
    if enc == ENC_ANSI || enc == ENC_UTF16BE || enc == ENC_UTF16LE || enc == ENC_WCHAR
        throw(
            NotPortedError{T}(
                type, string("open/4 with the stream encoding ", enc),
                "UTF-8 only (R1, user 2026-10-07)"
            )
        )
    end
    fnewline = -1
    if newline !== nothing && !_sym_is(type, :binary)
        nm = atom_to_newline_mode(ld, newline, how[1] == 'r' ? SIO_INPUT : SIO_OUTPUT)
        nm === nothing && return nothing
        fnewline = nm
    end

    bom == -1 && (bom = _sym_is(mname, :read) ? 1 : 0)
    _sym_is(type, :binary) && push!(how, 'b')

    if !_sym_is(lock, :none)                                    # File locking
        if !(
            _sym_is(lock, :read) || _sym_is(lock, :shared) || _sym_is(lock, :write) ||
            _sym_is(lock, :exclusive)
        )
            l = PL_new_term_ref(ld)
            PL_put_atom(ld, l, lock)
            PL_error(ld, ERR_DOMAIN, mk_sym(T, :lock), l)
            return nothing
        end
        throw(
            NotPortedError{T}(
                lock, "open/4's lock(Lock) option (advisory file locks)", "no flock"
            )
        )
    end

    if alias !== nothing &&
        (
        standardStreamIndexFromName(ld, alias) >= 0 ||
        haskey(gd.stream_aliases, sym_key(alias))
    )
        aliast = PL_new_term_ref(ld)
        PL_cons_functor(ld, aliast, _err_functor(ld, :alias, 1), _err_atom(ld, alias))
        PL_error(
            ld, "", 0, "", ERR_PERMISSION, mk_sym(T, :open), mk_sym(T, :source_sink), aliast
        )
        return nothing
    end

    if PL_is_functor(ld, file, mk_sym(T, :pipe), 1)             # FILE
        throw(NotPortedError{T}(mk_sym(T, :pipe), "open(pipe(Command), …)", "Sopen_pipe"))
    end
    path = PL_get_file_name(ld, file, 0)
    path === nothing && return nothing
    s, errno = Sopen_file(path, String(how))
    if s === nothing
        PL_error(                                               # error:
            ld, "", 0, Base.Libc.strerror(errno), ERR_FILE_OPERATION, mk_sym(T, :open),
            mk_sym(T, :source_sink), file, errno
        )
        return nothing
    end
    setFileNameStream(gd, s, mk_sym(T, Symbol(path)))

    s.encoding = enc
    fnewline == -1 || (s.newline = fnewline & 0x3)
    close_on_abort || (s.flags |= SIO_NOCLOSE)

    if how[1] == 'r'
        if !set_eof_action(ld, s, eof_action)
            Sclose(s)
            freeStream(ld, s)
            return nothing
        end
    elseif !_sym_is(buffer, :full) && !set_buffering(ld, s, buffer)
        Sclose(s)
        freeStream(ld, s)
        return nothing
    end

    alias === nothing || aliasStream(gd, s, alias)
    reposition || (s.position = nothing)

    if bom != 0
        bom_ok = true
        if _sym_is(mname, :read)
            bom_ok = ScheckBOM(s) >= 0
        elseif _sym_is(mname, :write) ||
            ((_sym_is(mname, :append) || _sym_is(mname, :update)) && Ssize(s) == 0)
            bom_ok = SwriteBOM(s) >= 0
        end
        if !bom_ok                                              # bom_error:
            streamStatus(ld, s)
            Sclose(s)
            freeStream(ld, s)
            return nothing
        end
    end

    return s
end

# PORT: pl-file.c open4 as pl_open4_va
# (PRED_IMPL("open", 4, open4, PL_FA_ISO))
function pl_open4_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3, A4 = PL__t0, PL__t0 + 1, PL__t0 + 2, PL__t0 + 3
    s = openStream(ld, A1, A2, A4)
    s === nothing && return FFALSE
    return PL_unify_stream_or_alias(ld, A3, s) ? FTRUE : FFALSE
end

# PORT: pl-file.c open3 as pl_open3_va
# (PRED_IMPL("open", 3, open3, PL_FA_ISO))
function pl_open3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    s = openStream(ld, A1, A2, 0)
    s === nothing && return FFALSE
    return PL_unify_stream_or_alias(ld, A3, s) ? FTRUE : FFALSE
end

# ── close/1,2 (pl-file.c) ───────────────────────────────────────────────────────────────────────

# PORT: pl-file.c closeStream
# DIVERGES: `Sclose` leaves the error to its caller, which reports it (upstream: inside `S__close`);
# the standard streams are those of `ld` (upstream's process-wide `Sinput`, `Soutput`, `Serror`);
# `freeStream` runs after `Sclose` (upstream: the close hook); no lock to release.
"Close the stream `s` at the Prolog level: never a standard stream, which is only flushed (pl-file.c)."
function closeStream(ld::PL_local_data, s::IOSTREAM)::Bool
    if s === Suser_input(ld)
        Sclearerr(s)
        return true
    elseif s === Suser_output(ld) || s === Suser_error(ld)
        Sflush(s) < 0 && return streamStatus(ld, s)
        return true
    end

    if Sferror(s) == 0 && Sflush(s) < 0
        rc = reportStreamError(ld, s)
        Sclose(s)
        freeStream(ld, s)
        return rc
    end
    rc = Sclose(s)
    rc < 0 && reportStreamError(ld, s)              # S__close: reportStreamError(s)
    freeStream(ld, s)
    return rc == 0
end

# PORT: pl-file.c do_close
# DIVERGES: `s` is `nothing` for upstream's NULL (a stream that is closed or no stream).
"Close `s`; with `force`, ignoring errors, and succeeding on no stream (pl-file.c)."
function do_close(
    ld::PL_local_data, s::Union{Nothing, IOSTREAM}, force::Bool
)::Bool
    if force
        s === nothing && return true
        if s === Suser_input(ld)
            Sclearerr(s)
        elseif s === Suser_output(ld) || s === Suser_error(ld)
            Sflush(s)
            Sclearerr(s)
        else
            Sflush(s)
            Sclose(s)
            freeStream(ld, s)
        end
        return true
    elseif s !== nothing
        return closeStream(ld, s)
    end
    return false
end

# PORT: pl-file.c pl_close
# DIVERGES: a pair is NOT PORTED.
"Close the stream (blob or alias) term reference `stream` holds (pl-file.c)."
function pl_close(ld::PL_local_data{T}, stream::term_t, force::Bool)::Bool where {T}
    _initIO(ld)
    a = PL_get_atom(ld, stream)
    a === nothing && return not_a_stream(ld, stream, SH_ALIAS)

    gd = _query_gd(ld)
    ref = _stream_ref_of(ld, a)
    if ref !== nothing                                          # close(Stream[pair], ...)
        (ref.read != 0 && ref.write != 0) && throw(
            NotPortedError{T}(a, "closing a stream pair", "stream_pair/3 (not ported)")
        )
        s = _stream_of(gd, ref.read != 0 ? ref.read : ref.write)
        rc = do_close(ld, s === nothing ? nothing : getStream(s), force)

        if !rc && ld.exception_term == 0
            rc = PL_error(
                ld, "", 0, "already closed", ERR_EXISTENCE, mk_sym(T, :stream), stream
            )
        end
        return rc
    end

    s = get_stream_handle(ld, a, SH_ERRORS | SH_ALIAS)          # close(Alias, ...)
    s === nothing && return false
    return do_close(ld, s, force)
end

# PORT: pl-file.c close as pl_close1_va
# (PRED_IMPL("close", 1, close, PL_FA_ISO))
function pl_close1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return pl_close(ld, PL__t0, false) ? FTRUE : FFALSE
end

# PORT: pl-file.c close2_options
const close2_options = (PL_option_t(:force, OPT_BOOL),)

# PORT: pl-file.c close2 as pl_close2_va
# (PRED_IMPL("close", 2, close2, PL_FA_ISO))
function pl_close2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    vals = PL_scan_options(ld, A2, 0, "close_option", close2_options)
    vals === nothing && return FFALSE
    force = vals[1] === true
    return pl_close(ld, A1, force) ? FTRUE : FFALSE
end

# PORT: pl-file.c source_location as pl_source_location2_va
# (PRED_IMPL("source_location", 2, source_location, 0)) — swipl-devel cbf4e189, src/os/pl-file.c:5805-5814
# DIVERGES: `source_file_name` is `ld.read_source.file` (the atom, `nothing` for NULL_ATOM), `source_line_no`
# its `position.lineno` (pl-global.h:927-928).
"`source_location(-File, -Line)` (pl-file.c): where the term read last starts, while a file is being read."
function pl_source_location2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    if ReadingSource(ld) &&
        PL_unify_atom(ld, A1, ld.read_source.file::T) &&
        PL_unify_integer(ld, A2, ld.read_source.position.lineno)
        return FTRUE
    end
    return FFALSE
end

# PORT: pl-file.c set_source_location as pl_set_source_location2_va
# (PRED_IMPL("$set_source_location", 2, set_source_location, 0)) — pl-file.c:5817-5822
"`'\$set_source_location'(+File, +Line)` (pl-file.c): set the file and line `source_location/2` answers."
function pl_set_source_location2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    a = PL_get_atom_ex(ld, A1)
    a === nothing && return FFALSE
    n = PL_get_integer_ex(ld, A2)
    n === nothing && return FFALSE
    ld.read_source.file = a                         # source_file_name = a
    ld.read_source.position.lineno = n              # source_line_no = n
    return FTRUE
end

# PORT: pl-file.c BeginPredDefs as PL_predicates_from_file
# DIVERGES: the entries of the predicates the kernel has ported (S1: open/3,4 and close/1,2; LB2:
# source_location/2 and '$set_source_location'/2, upstream's order file:6396-6397); `PRED_DEF` ors in `PL_FA_VARARGS`.
"pl-file.c's registration table (`BeginPredDefs(file)`): the ported entries."
const PL_predicates_from_file = (
    PL_extension("open", 4, pl_open4_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("open", 3, pl_open3_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("close", 1, pl_close1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("close", 2, pl_close2_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("source_location", 2, pl_source_location2_va, PL_FA_VARARGS),
    PL_extension("\$set_source_location", 2, pl_set_source_location2_va, PL_FA_VARARGS)
)
