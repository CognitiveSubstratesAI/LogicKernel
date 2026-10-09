# UPSTREAM: swipl-devel src/os/pl-file.c @ bae881a2
# UPSTREAM: swipl-devel src/os/pl-file.h @ bae881a2
# UPSTREAM: swipl-devel src/pl-global.h @ bae881a2
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
# (`getOutputStream`), with upstream's errors, and a stream's error state (`streamStatus`). NOT
# PORTED: the rest of the stream table — user aliases, stream blobs, open/close/4, the stream
# properties, input streams for read/1 (R2); no locks (no threads).

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

# A standard stream over the process's `io` with `flags` (pl-stream.c `S__iob0`), or `nothing` when
# the IO is none the stream layer can hold (`Sjulia_io`): `SIO_ISATTY` only on a terminal
# (pl-stream.c `SinitStreams`).
function _std_stream(io::IO, flags::UInt32)::Union{Nothing, IOSTREAM}
    io isa Union{IOStream, IOBuffer, Base.TTY, Base.PipeEndpoint} || return nothing
    io isa Base.TTY || (flags &= ~SIO_ISATTY)
    return Snew(Sjulia_io(io, false), flags, Siofunctions)
end

# PORT: pl-file.c initIO
# DIVERGES: per local data, the FIRST TIME a standard stream is asked for (a new local data opens no
# stream; the host may replace them, `set_standard_stream!`), where upstream opens them at start-up:
# `Sinput`, `Soutput` and `Serror` (pl-stream.c `S__iob0`'s flags: line-buffered input and output,
# an unbuffered error stream) over Julia's stdin, stdout and stderr; the three share `Sinput`'s
# position record, as upstream. No tty modes, no protocol stream (`Sprotocol` stays NULL), no stream
# contexts or alias table (the aliases are `standardStreams`).
"Open the standard streams of `ld` over the process's stdin, stdout and stderr (pl-file.c)."
function initIO(ld::PL_local_data)::Nothing
    sin = _std_stream(Base.stdin, SIO_STDIO | SIO_LBUF | SIO_INPUT | SIO_NOFEOF)
    sout = _std_stream(Base.stdout, SIO_STDIO | SIO_LBUF | SIO_OUTPUT | SIO_REPPLU)
    serr = _std_stream(Base.stderr, SIO_STDIO | SIO_NBUF | SIO_OUTPUT | SIO_REPPLU)
    if sin !== nothing
        sin.position = sin.posbuf                   # position logging
        sout === nothing || (sout.position = sin.posbuf)
        serr === nothing || (serr.position = sin.posbuf)
    end

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
    ld.slots[t + 1] = symbol                        # PL_put_atom(t, symbol)
    return no_stream(ld, t, :stream)
end

# PORT: pl-file.c symbol_stream_wrong_mode
"Raise `permission_error(Action, stream, Symbol)`, 'requested stream has wrong mode' (pl-file.c); false."
function symbol_stream_wrong_mode(
    ld::PL_local_data{T}, symbol::T, action::Symbol
)::Bool where {T}
    t = PL_new_term_ref(ld)
    ld.slots[t + 1] = symbol                        # PL_put_atom(t, symbol)
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
# DIVERGES: the alias table is the standard streams' (no stream blobs, no user aliases: R2), so an
# atom is a standard stream's name or no stream; returns the stream or `nothing`; no locks. A
# standard name whose stream is NULL — `protocol` — is `existence_error(stream, protocol)`: upstream
# releases the file lock twice on that path, `PL_UNLOCK(L_FILE)` inside the alias branch and again
# before `goto noent`, and swipl 10.1.16 aborts on it (`countingMutexUnlock: Assertion failed`;
# repro: docs/tracking/repros/ in the workspace) — the kernel takes the path upstream intends.
"The stream the atom `a` names, as `flags` (`SH_*`) ask, or `nothing` with the error raised (pl-file.c)."
function get_stream_handle(
    ld::PL_local_data{T}, a::T, flags::Int
)::Union{Nothing, IOSTREAM} where {T}
    n = standardStreamIndexFromName(ld, a)          # lookupHTableWP(streamAliases, a)
    if n >= 0
        stream = ld.IO_streams[n + 1]               # LD->IO.streams[n]
        if stream !== nothing
            check_stream_mode(ld, a, stream, flags) || return nothing
            return stream
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
        ld.slots[t + 1] = mk_sym(T, :current_output)    # PL_put_atom(t, ATOM_current_output)
    end
    PL_error(ld, "", 0, "", ERR_PERMISSION, mk_sym(T, :output), mk_sym(T, tp), t)

    return nothing
end

# PORT: pl-file.c getTextOutputStream
"The text output stream term reference `t` names (0: the current output), or `nothing` (pl-file.c)."
getTextOutputStream(ld::PL_local_data{T}, t::term_t) where {T} =
    getOutputStream(ld, t, S_TEXT)

# PORT: pl-file.c PL_unify_stream_or_alias
# DIVERGES: a standard stream's alias only — every stream the kernel opens is one (stream blobs
# and user aliases: R2).
"Unify term reference `t` with the alias of the standard stream `s` (pl-file.c)."
function PL_unify_stream_or_alias(
    ld::PL_local_data{T}, t::term_t, s::IOSTREAM
)::Bool where {T}
    i = standardStreamIndexFromStream(ld, s)
    @assert 0 <= i < 3 "PL_unify_stream_or_alias: not a standard stream (stream blobs: R2)"
    return PL_unify_atom(ld, t, mk_sym(T, standardStreams[i + 1]))
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
            rc = printMessage(
                ld, :warning,
                mk_expr(
                    T,
                    T[
                        mk_sym(T, :io_warning), ld.slots[stream + 1],
                        mk_sym(T, Symbol(something(s.message, "")))
                    ]
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
