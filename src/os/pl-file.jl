# UPSTREAM: swipl-devel src/os/pl-file.c @ 18168e629eab
# UPSTREAM: swipl-devel src/os/pl-file.h @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-global.h @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-incl.h @ 18168e629eab
# UPSTREAM: swipl-devel src/os/pl-stream.c @ 18168e629eab
# UPSTREAM: swipl-devel src/pl-privitf.c @ 18168e629eab
# UPSTREAM: swipl-devel src/os/pl-prologflag.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# PIN1 ledger (V10.1.20): re-cite only, no code change (cbf4e189..18168e62 compared, D-0447 Q1) — pl-incl.h: access-only (d755bdc4) ported; ATOM_RESERVE_BATCH is pl-incl.jl:460 (commit 5); the PLFLAG_EPILOG comma is no value; pl-prologflag.c: flags validate_api and the tabling restraint flags ported, 1412ce49 ported. Also re-cited: pl-file.c: set_eof_action, newline mode (cd67bb35, dfc1c55d, 4f259069) ported; shareStandardStream (87fc7589) is owner TH1 (docs/architecture.md, deferred owners); pl-global.h: the unported fields are the tabling fields (TAB1 row cfile:pl-tabling.c), LD->profile (PROF1) and LD->atoms.reserved (ATOM1), owners in docs/architecture.md (deferred owners); pl-stream.c: Sshare (87fc7589) is owner TH1 (docs/architecture.md, deferred owners).
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
# input streams for read/1, the
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

# PORT: pl-file.c SH_NOPAIR
"Stream lookup flag: a stream pair is ambiguous (pl-file.c)."
const SH_NOPAIR = Int(0x20)

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
# DIVERGES: per local data, when `PL_local_data{T}(gd)` makes it (the host may replace the streams,
# `set_standard_stream!`), where upstream opens them once for the process at start-up (setupProlog,
# pl-setup.c:173, which every thread's local data then references): `Sinput`, `Soutput` and `Serror` (pl-stream.c `S__iob0`'s flags: line-buffered input and output,
# an unbuffered error stream) over Julia's stdin, stdout and stderr (`_std_io`); the three share `Sinput`'s
# position record, as upstream. No tty modes, no protocol stream (`Sprotocol` stays NULL), no alias
# table (the aliases are `standardStreams`); the three streams are made known to Prolog
# (`getStreamContext`, pl-file.c initIO "add for enumeration").
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
    gd = _query_gd(ld)
    getStreamContext(gd, sin)                       # add for enumeration
    getStreamContext(gd, sout)
    getStreamContext(gd, serr)
    ld.IO_initialised = true
    return nothing
end

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
# being gone from the table (upstream: `s->erased`). A pair (both `read` and `write`) selects its
# output stream for `SH_OUTPUT`, its input stream for `SH_INPUT`, else (`SH_NOPAIR`) the flag
# `error_ambiguous_stream_pair` decides between `type_error(stream, Pair)` and a warning message and the
# input stream; no `assert` on the reference counts. The alias table is the standard streams' names and the user aliases; returns the
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
        local sn::Int
        if ref.read != 0
            if ref.write != 0
                if (flags & SH_OUTPUT) != 0
                    sn = ref.write
                elseif (flags & SH_INPUT) != 0
                    sn = ref.read
                elseif (flags & SH_NOPAIR) != 0
                    if truePrologFlag(ld, PLFLAG_ERROR_AMBIGUOUS_STREAM_PAIR)
                        symbol_stream_pair_not_allowed(ld, a)   # the error, false
                        return nothing
                    else
                        t = PL_new_term_ref(ld)
                        setSlotValue!(ld, t + 1, a)             # PL_put_atom(t, a)
                        printMessage(
                            ld, :warning, _message_term(ld, :ambiguous_stream_pair, t)
                        ) || return nothing
                        sn = ref.read
                    end
                else
                    sn = ref.read
                end
            else
                sn = ref.read
            end
        else
            sn = ref.write
        end
        s = _stream_of(gd, sn)
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
# pointer. A pair has both set (`stream_pair/3`).
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
        delete!(gd.stream_context_flags, s.context)   # ctx->flags
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

# PORT: pl-file.c stream_pair as pl_stream_pair3_va
# (PRED_IMPL("stream_pair", 3, stream_pair, 0)) — pl-file.c:1266-1330 (pin 18168e62)
# DIVERGES: the pair's blob holds the streams' table numbers (`stream_ref`); no reference counts
# (`acquire_stream_ref` is a hook the kernel has no twin of: no atom GC), no lock to release. A blob is unique
# by payload, so the same two streams give the same pair.
"`stream_pair(?Pair, ?Read, ?Write)`: split a pair into its streams, or make a pair of two (pl-file.c)."
function pl_stream_pair3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2

    if !PL_is_variable(ld, A1)
        a = PL_get_atom(ld, A1)
        ref = a === nothing ? nothing : _stream_ref_of(ld, a)
        gd = _query_gd(ld)
        if ref !== nothing                                  # type == &stream_blob
            rc = true
            rs = ref.read != 0 ? _stream_of(gd, ref.read) : nothing
            if rs !== nothing && !rs.erased
                rc = rc && PL_unify_stream_or_alias(ld, A2, rs)
            end
            ws = ref.write != 0 ? _stream_of(gd, ref.write) : nothing
            if ws !== nothing && !ws.erased
                rc = rc && PL_unify_stream_or_alias(ld, A3, ws)
            end
            return rc ? FTRUE : FFALSE
        else
            if a !== nothing
                s = get_stream_handle(ld, a, SH_ERRORS | SH_ALIAS | SH_UNLOCKED)
                if s !== nothing
                    rc = if (s.flags & SIO_INPUT) != 0
                        PL_unify_stream_or_alias(ld, A2, s)
                    else
                        PL_unify_stream_or_alias(ld, A3, s)
                    end
                    return rc ? FTRUE : FFALSE
                end
            end

            rc = PL_error(ld, "", 0, "", ERR_TYPE, mk_sym(T, :stream_pair), A1)
            return rc ? FTRUE : FFALSE
        end
    end

    in = getInputStream(ld, A2, S_DONTCARE)
    in === nothing && return FFALSE
    out = getOutputStream(ld, A3, S_DONTCARE)
    out === nothing && return FFALSE
    gd = _query_gd(ld)
    pair = stream_ref(getStreamContext(gd, in), getStreamContext(gd, out))
    return PL_unify_atom(ld, A1, _stream_blob_term(ld, pair)) ? FTRUE : FFALSE
end

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
# the table, `PL_encoding_to_atom` reads it backwards (S2a: the stream property `encoding/1`).
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

# The process's own standard streams (`Sinput`, `Soutput`, `Serror`, pl-stream.c `S__iob0`) as the tests of
# `closeStream` and `do_close` (pl-file.c:1503-1521, 4668-4690) take them: NOT the streams `user_input`,
# `user_output` and `user_error` are bound to now (a file stream under `set_stream(S, alias(user_input))` is
# no `Sinput`), but the streams `initIO`, `set_standard_stream!` and `restoreStandardStream` make, which are the
# only streams carrying `SIO_STATIC` (static: not allocated by `Snew` for an `open/3`).
# ORIGINAL: upstream's `Sinput` is one process-wide object compared by address; the kernel keeps no permanent
# stream (`restoreStandardStream` makes a new one, and a host replaces them), so the test is the stream's
# `SIO_STATIC` flag and its direction, which only the standard streams carry.
"Whether `s` is the process's standard input, upstream's `Sinput` (pl-file.c)."
isSinput(s::IOSTREAM)::Bool =
    (s.flags & (SIO_STATIC | SIO_INPUT)) == (SIO_STATIC | SIO_INPUT)
"Whether `s` is the process's standard output or error, upstream's `Soutput` or `Serror` (pl-file.c)."
isSoutputOrSerror(s::IOSTREAM)::Bool =
    (s.flags & (SIO_STATIC | SIO_OUTPUT)) == (SIO_STATIC | SIO_OUTPUT)

# PORT: pl-file.c closeStream
# (pl-file.c:1503-1521, faithful: `s == Sinput`; `s == Soutput || s == Serror`; else flush and `Sclose`)
# DIVERGES: `Sclose` leaves the error to its caller, which reports it (upstream: inside `S__close`);
# `freeStream` runs after `Sclose` (upstream: the close hook); no lock to release.
"Close the stream `s` at the Prolog level: never a standard stream, which is only flushed (pl-file.c)."
function closeStream(ld::PL_local_data, s::IOSTREAM)::Bool
    if isSinput(s)
        Sclearerr(s)
        return true
    elseif isSoutputOrSerror(s)
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
        if isSinput(s)
            Sclearerr(s)
        elseif isSoutputOrSerror(s)
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
# DIVERGES: a stream the blob's number no longer names in the table is upstream's `erased` stream (a pair's closed
# half is skipped, as there); no `assert` on the reference counts.
"Close the stream (blob or alias) term reference `stream` holds (pl-file.c)."
function pl_close(ld::PL_local_data{T}, stream::term_t, force::Bool)::Bool where {T}
    a = PL_get_atom(ld, stream)
    a === nothing && return not_a_stream(ld, stream, SH_ALIAS)

    gd = _query_gd(ld)
    ref = _stream_ref_of(ld, a)
    if ref !== nothing                                          # close(Stream[pair], ...)
        rc = true
        if ref.read != 0 && ref.write != 0
            ws = _stream_of(gd, ref.write)
            if ws !== nothing && !ws.erased
                rc = do_close(ld, getStream(ws), force)
            end
            rs = _stream_of(gd, ref.read)
            if rs !== nothing && !rs.erased
                rc = do_close(ld, getStream(rs), force) && rc
            end
        else
            s = _stream_of(gd, ref.read != 0 ? ref.read : ref.write)
            rc = do_close(ld, s === nothing ? nothing : getStream(s), force)
        end

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

# ── TEMPORARY I/O: the input context, see and seen (R2 LB3: the boot loop's `pl_see`/`pl_seen`) ─────

# PORT: pl-file.c push_input_context
# (swipl-devel cbf4e189, src/os/pl-file.c:1583-1598)
# DIVERGES: the context is pushed on `ld.input_context_stack` (a vector; upstream: a heap cell linked to
# `previous`); no atom reference counts (no atom garbage collection).
"Save the current input stream and source location as a context of `type` (pl-file.c)."
function push_input_context(ld::PL_local_data{T}, type::T)::Bool where {T}
    c = input_context{T}(
        Scurin(ld),                                 # c->stream    = Scurin
        type,                                       # c->type      = type
        ld.read_source.file,                        # c->term_file = source_file_name
        ld.read_source.position.lineno              # c->term_line = source_line_no
    )
    push!(ld.input_context_stack, c)                # c->previous = input_context_stack; input_context_stack = c
    return true
end

# PORT: pl-file.c pop_input_context
# (swipl-devel cbf4e189, src/os/pl-file.c:1601-1619)
# DIVERGES: as `push_input_context`; upstream's `Sinput` is `Suser_input(ld)` (`initIO`, above).
"Restore the input stream and source location the last `push_input_context` saved; false when none is saved (pl-file.c)."
function pop_input_context(ld::PL_local_data{T})::Bool where {T}
    if !isempty(ld.input_context_stack)
        c = pop!(ld.input_context_stack)
        ld.IO_streams[SNO_CURRENT_INPUT + 1] = c.stream    # Scurin           = c->stream
        ld.read_source.file = c.term_file                   # source_file_name = c->term_file
        ld.read_source.position.lineno = c.term_line        # source_line_no   = c->term_line
        return true
    else
        ld.IO_streams[SNO_CURRENT_INPUT + 1] = Suser_input(ld)   # Scurin = Sinput
        return false
    end
end

# PORT: pl-file.c IO_TELL
"The stream-context flag of a stream opened by tell/1 (pl-file.c)."
const IO_TELL = 0x001
# PORT: pl-file.c IO_SEE
"The stream-context flag of a stream opened by see/1 (pl-file.c)."
const IO_SEE = 0x002

# ORIGINAL: upstream's `set(getStreamContext(s), flag)`; the flags are `PL_global_data.stream_context_flags`, by the
# stream's context number (upstream: `stream_context.flags`).
"Set the stream-context flag `flag` of `s`, making the stream known first (pl-file.c `set(getStreamContext(s), flag)`)."
function setStreamContextFlag(gd::PL_global_data, s::IOSTREAM, flag::Int)::Nothing
    ctx = getStreamContext(gd, s)
    gd.stream_context_flags[ctx] = get(gd.stream_context_flags, ctx, 0) | flag
    return nothing
end

# PORT: pl-file.c findStreamFromFile
# DIVERGES: `newTableEnumPP(streamContext)` is the live entries of `PL_global_data.stream_table`, in the order the
# streams got their context (upstream: hash-table order); `ison(ctx, flags)` is a read of `stream_context_flags`.
"The stream that reads or writes the file named `name` and carries the context flag `flags`, or `nothing` (pl-file.c)."
function findStreamFromFile(gd::PL_global_data{T}, name::T, flags::Int)::Union{Nothing, IOSTREAM} where {T}
    for s in gd.stream_table
        s === nothing && continue
        fn = fileNameStream(gd, s)
        if fn !== nothing && sym_key(fn) == sym_key(name) &&
           (get(gd.stream_context_flags, s.context, 0) & flags) != 0
            return s
        end
    end
    return nothing
end

# PORT: pl-file.c pl_see
# (swipl-devel cbf4e189, src/os/pl-file.c:4446-4485)
# DIVERGES: `findStreamFromFile` is `findStreamFromFile(gd, a, IO_SEE)` (above); `set(getStreamContext(s), IO_SEE)` is
# `setStreamContextFlag`. No lock (no threads).
"Make the stream alias, `user` or the file the atom `f` names the current input, opening the file for reading (pl-file.c)."
function pl_see(ld::PL_local_data{T}, f::term_t)::Bool where {T}
    gd = _query_gd(ld)
    a = PL_get_atom_ex(ld, f)
    a === nothing && return false

    s = get_stream_handle(ld, a, SH_ALIAS | SH_UNLOCKED)
    if s !== nothing
        ld.IO_streams[SNO_CURRENT_INPUT + 1] = s    # Scurin = s
        return true
    end
    if sym_key(a) == sym_key(mk_sym(T, :user))      # a == ATOM_user
        ld.IO_streams[SNO_CURRENT_INPUT + 1] = Suser_input(ld)   # Scurin = Suser_input
        return true
    end
    s = findStreamFromFile(gd, a, IO_SEE)
    if s !== nothing
        ld.IO_streams[SNO_CURRENT_INPUT + 1] = s    # Scurin = s
        return true
    end

    mode = PL_new_term_ref(ld)
    PL_put_atom(ld, mode, mk_sym(T, :read))         # PL_put_atom(mode, ATOM_read)
    s = openStream(ld, f, mode, 0)
    s === nothing && return false

    setStreamContextFlag(gd, s, IO_SEE)             # set(getStreamContext(s), IO_SEE)
    push_input_context(ld, mk_sym(T, :see))         # push_input_context(ATOM_see)
    ld.IO_streams[SNO_CURRENT_INPUT + 1] = s        # Scurin = s
    return true
end

# PORT: pl-file.c pl_seen
# (swipl-devel cbf4e189, src/os/pl-file.c:4487-4501)
"Close the current input stream, unless it is one that ignores end of file, and restore the input context before it (pl-file.c)."
function pl_seen(ld::PL_local_data{T})::Bool where {T}
    cur = Scurin(ld)
    s = cur === nothing ? nothing : getStream(cur)  # getStream(Scurin)

    pop_input_context(ld)

    s !== nothing && (s.flags & SIO_NOFEOF) != 0 && return true

    s !== nothing && return closeStream(ld, s)

    return symbol_no_stream(ld, mk_sym(T, :current_input))
end

# PORT: pl-file.c see as pl_see1_va
# (PRED_IMPL("see", 1, see, 0)) — pl-file.c:4546-4549 (pin 18168e62)
"`see(+SrcDest)`: make a stream, alias, `user` or the file named the current input (pl-file.c)."
function pl_see1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return pl_see(ld, PL__t0) ? FTRUE : FFALSE
end

# PORT: pl-file.c seen as pl_seen0_va
# (PRED_IMPL("seen", 0, seen, 0)) — pl-file.c:4552-4555 (pin 18168e62)
"`seen`: close the current input and restore the one before the `see/1` (pl-file.c)."
function pl_seen0_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return pl_seen(ld) ? FTRUE : FFALSE
end

# PORT: pl-file.c seeing as pl_seeing1_va
# (PRED_IMPL("seeing", 1, seeing, 0)) — pl-file.c:4558-4566 (pin 18168e62)
"`seeing(-SrcDest)`: `user` for the user's input, else the current input stream (pl-file.c)."
function pl_seeing1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    if Scurin(ld) === Suser_input(ld)
        return PL_unify_atom(ld, PL__t0, mk_sym(T, :user)) ? FTRUE : FFALSE
    end
    return PL_unify_stream(ld, PL__t0, Scurin(ld)::IOSTREAM) ? FTRUE : FFALSE
end

# PORT: pl-file.c do_tell
# DIVERGES: no lock (no threads: `PL_LOCK(L_SEETELL)`); `m` is the open mode atom (`ATOM_write` or `ATOM_append`);
# `findStreamFromFile` and `set(getStreamContext(s), IO_TELL)` as `pl_see`.
"Make a stream, alias, `user` or the file `f` names the current output, opening the file in mode `m` (pl-file.c)."
function do_tell(ld::PL_local_data{T}, f::term_t, m::T)::Bool where {T}
    gd = _query_gd(ld)
    a = PL_get_atom_ex(ld, f)
    a === nothing && return false

    s = get_stream_handle(ld, a, SH_UNLOCKED)
    if s !== nothing
        setStandardStream(ld, SNO_CURRENT_OUTPUT, s)
        return true
    end
    if sym_key(a) == sym_key(mk_sym(T, :user))      # a == ATOM_user
        setStandardStream(ld, SNO_CURRENT_OUTPUT, Suser_output(ld)::IOSTREAM)
        return true
    end
    s = findStreamFromFile(gd, a, IO_TELL)
    if s !== nothing
        setStandardStream(ld, SNO_CURRENT_OUTPUT, s)
        return true
    end

    mode = PL_new_term_ref(ld)
    PL_put_atom(ld, mode, m)                        # PL_put_atom(mode, m)
    s = openStream(ld, f, mode, 0)
    s === nothing && return false

    setStreamContextFlag(gd, s, IO_TELL)            # set(getStreamContext(s), IO_TELL)
    pushOutputContext(ld, s)
    return true
end

# PORT: pl-file.c tell as pl_tell1_va
# (PRED_IMPL("tell", 1, tell, 0)) — pl-file.c:4611-4614 (pin 18168e62)
"`tell(+SrcDest)`: make a stream, alias, `user` or the file named the current output, opened for writing (pl-file.c)."
function pl_tell1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return do_tell(ld, PL__t0, mk_sym(T, :write)) ? FTRUE : FFALSE
end

# PORT: pl-file.c append as pl_append1_va
# (PRED_IMPL("append", 1, append, 0)) — pl-file.c:4616-4619 (pin 18168e62)
"`append(+File)`: as `tell/1`, the file opened for appending (pl-file.c)."
function pl_append1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return do_tell(ld, PL__t0, mk_sym(T, :append)) ? FTRUE : FFALSE
end

# PORT: pl-file.c telling as pl_telling1_va
# (PRED_IMPL("telling", 1, telling, 0)) — pl-file.c:4621-4629 (pin 18168e62)
"`telling(-SrcDest)`: `user` for the user's output, else the current output stream (pl-file.c)."
function pl_telling1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    if Scurout(ld) === Suser_output(ld)
        return PL_unify_atom(ld, PL__t0, mk_sym(T, :user)) ? FTRUE : FFALSE
    end
    return PL_unify_stream(ld, PL__t0, Scurout(ld)::IOSTREAM) ? FTRUE : FFALSE
end

# PORT: pl-file.c told as pl_told0_va
# (PRED_IMPL("told", 0, told, 0)) — pl-file.c:4631-4645 (pin 18168e62)
"`told`: close the current output and restore the one before the `tell/1` (pl-file.c)."
function pl_told0_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    cur = Scurout(ld)
    s = cur === nothing ? nothing : getStream(cur)  # getStream(Scurout)

    popOutputContext(ld)

    s !== nothing && (s.flags & SIO_NOFEOF) != 0 && return FTRUE

    s !== nothing && return closeStream(ld, s) ? FTRUE : FFALSE

    return symbol_no_stream(ld, mk_sym(T, :current_output)) ? FTRUE : FFALSE
end

# ── NULL-STREAM (pl-file.c, pin 18168e62:4646-4713) ─────────────────────────────────────────────

# PORT: pl-file.c Swrite_null
# DIVERGES: `buf` is `mem` from `from`; no handle (`Snullfunctions` streams hold `nothing`).
"The write function of a null stream: every byte is taken (pl-file.c)."
Swrite_null(mem::Vector{UInt8}, from::Int, size::Int)::Int = size

# PORT: pl-file.c Sread_null
# DIVERGES: as `Swrite_null`.
"The read function of a null stream: always at the end (pl-file.c)."
Sread_null(mem::Vector{UInt8}, from::Int, size::Int)::Int = 0

# PORT: pl-file.c Sseek_null
# DIVERGES: `S_seek64` (pl-stream.jl) calls this where upstream's function set holds it as the `seek` pointer, with the offset
# as an `Int`; a seek to an absolute position answers it, the other whences -1, as upstream.
"The seek function of a null stream (pl-file.c)."
function Sseek_null(offset::Int, whence::Int)::Int
    whence == SIO_SEEK_SET && return offset
    return -1
end

# PORT: pl-file.c Sclose_null
# DIVERGES: as `Swrite_null`.
"The close function of a null stream (pl-file.c)."
Sclose_null()::Int = 0

# PORT: pl-file.c open_null_stream as pl_open_null_stream1_va
# (PRED_IMPL("open_null_stream", 1, open_null_stream, 0)) — pl-file.c:4698-4710 (pin 18168e62)
"`open_null_stream(-Stream)`: a text output stream that discards what is written to it (pl-file.c)."
function pl_open_null_stream1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    sflags = SIO_NBUF | SIO_RECORDPOS | SIO_OUTPUT | SIO_TEXT
    s = Snew(nothing, sflags, Snullfunctions)
    s.encoding = ENC_UTF8
    return PL_unify_stream_or_alias(ld, PL__t0, s) ? FTRUE : FFALSE
end

# ── seek and set_stream_position (pl-file.c) ────────────────────────────────────────────────────

# PORT: pl-file.c getRepositionableStream
# DIVERGES: returns the stream or `nothing` (upstream: `bool` and `IOSTREAM **sp`); "has a `seek` function" is `S_has_seek`
# (the kernel's function sets are names, not pointer tables); no lock to release.
"The stream `stream` names (an atom), if it records a position and can seek, else `permission_error(reposition, stream, S)`."
function getRepositionableStream(
    ld::PL_local_data{T}, stream::term_t
)::Union{Nothing, IOSTREAM} where {T}
    a = PL_get_atom(ld, stream)
    if a === nothing
        not_a_stream(ld, stream, SH_ALIAS)
        return nothing
    end
    s = get_stream_handle(ld, a, SH_ERRORS)
    s === nothing && return nothing
    if s.position === nothing || !S_has_seek(s)
        _PL_permission_error(ld, :reposition, :stream, stream)
        return nothing
    end
    return s
end

# PORT: pl-file.c set_stream_position as pl_set_stream_position2_va
# (PRED_IMPL("set_stream_position", 2, set_stream_position, PL_FA_ISO)) — pl-file.c:5611-5650 (pin 18168e62)
"`set_stream_position(+Stream, +Pos)`: re-position `Stream` to `'\$stream_position'(Char, Line, LinePos, Byte)` (pl-file.c)."
function pl_set_stream_position2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    stream, pos = PL__t0, PL__t0 + 1
    a = PL_new_term_ref(ld)

    s = getRepositionableStream(ld, stream)
    s === nothing && return FFALSE

    charno = lineno = linepos = byteno = nothing
    if PL_is_functor(ld, pos, mk_sym(T, Symbol("\$stream_position")), 4) &&
        _PL_get_arg(ld, 1, pos, a)
        charno = PL_get_int64(ld, a)
        _PL_get_arg(ld, 2, pos, a) && (lineno = PL_get_long(ld, a))
        _PL_get_arg(ld, 3, pos, a) && (linepos = PL_get_long(ld, a))
        _PL_get_arg(ld, 4, pos, a) && (byteno = PL_get_int64(ld, a))
    end
    if charno === nothing || lineno === nothing || linepos === nothing || byteno === nothing
        rc = PL_error(
            ld, "stream_position", 3, "", ERR_DOMAIN, mk_sym(T, :stream_position), pos
        )
        return rc ? FTRUE : FFALSE
    end

    if Sseek64(s, Int64(byteno), SIO_SEEK_SET) != 0
        PL_error(
            ld, "", 0, MSG_ERRNO, ERR_FILE_OPERATION, mk_sym(T, :reposition),
            mk_sym(T, :stream), stream, s.io_errno
        )
        return FFALSE
    end

    p = s.position::IOPOS
    p.byteno = byteno
    p.charno = charno
    p.lineno = lineno
    p.linepos = linepos
    Sresetesc(p)

    return FTRUE
end

# PORT: pl-file.c seek as pl_seek4_va
# (PRED_IMPL("seek", 4, seek, 0)) — pl-file.c:5655-5707 (pin 18168e62)
# DIVERGES: `errno` is the stream's `io_errno` (see `Sseek64`); the message of the permission error is `strerror` of it,
# read before `Sclearerr` clears it (the sentinel `MSG_ERRNO` is only understood by `ERR_FILE_OPERATION`).
"`seek(+Stream, +Offset, +Method, -NewLocation)`: move `Stream`'s position (`bof`, `current`, `eof`), in units of its encoding (pl-file.c)."
function pl_seek4_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    stream, offset, method, newloc = PL__t0, PL__t0 + 1, PL__t0 + 2, PL__t0 + 3

    m = PL_get_atom_ex(ld, method)
    m === nothing && return FFALSE

    if _sym_is(m, :bof)
        whence = SIO_SEEK_SET
    elseif _sym_is(m, :current)
        whence = SIO_SEEK_CUR
    elseif _sym_is(m, :eof)
        whence = SIO_SEEK_END
    else
        rc = PL_error(ld, "seek", 4, "", ERR_DOMAIN, mk_sym(T, :seek_method), method)
        return rc ? FTRUE : FFALSE
    end

    off = PL_get_int64(ld, offset)
    if off === nothing
        rc = PL_error(ld, "seek", 4, "", ERR_DOMAIN, mk_sym(T, :integer), offset)
        return rc ? FTRUE : FFALSE
    end

    s = term_stream_handle(ld, stream, SH_ERRORS | SH_ALIAS | SH_NOPAIR)    # PL_get_stream_handle
    s === nothing && return FFALSE

    unit = Sunit_size(s)

    off *= unit
    if Sseek64(s, Int64(off), whence) < 0
        if s.io_errno == EINVAL
            PL_error(
                ld, "seek", 4, "offset out of range", ERR_DOMAIN, mk_sym(T, :position), offset
            )
        else
            PL_error(
                ld, "seek", 4, Base.Libc.strerror(s.io_errno), ERR_PERMISSION,
                mk_sym(T, :reposition), mk_sym(T, :stream), stream
            )
        end
        Sclearerr(s)
        return FFALSE
    end

    new = Stell64(s)
    new = div(new, unit)

    return PL_unify_int64(ld, newloc, Int(new)) ? FTRUE : FFALSE
end

# PORT: pl-file.c set_end_of_stream as pl_set_end_of_stream1_va
# (PRED_IMPL("set_end_of_stream", 1, set_end_of_stream, 0)) — pl-file.c:2634-2664 (pin 18168e62)
# DIVERGES: `Sfileno(s) >= 0` + `ftruncate(fileno, Stell64(s))` is a stream over a file's Julia IO (`IOStream`) and
# `truncate(io, Stell64(s))`, the IO's own buffer flushed first; every other stream "is not a file". `PL_get_stream(A1, &s,
# SIO_OUTPUT)` reads its own flags (`SIO_OUTPUT` has no `SH_ALIAS` bit: a non-atom is `domain_error(stream, X)`).
"`set_end_of_stream(+Stream)`: truncate the file of the output stream `Stream` at its current position (pl-file.c)."
function pl_set_end_of_stream1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    a = PL_get_atom(ld, A1)
    if a === nothing
        not_a_stream(ld, A1, Int(SIO_OUTPUT))
        return FFALSE
    end
    s = get_stream_handle(ld, a, SH_ERRORS | SH_ALIAS | SH_OUTPUT)
    s === nothing && return FFALSE

    h = s.handle
    if s.functions == Siofunctions && h isa Sjulia_io && h.io isa IOStream
        io = h.io::IOStream
        try
            flush(io)
            truncate(io, Stell64(s))
        catch e
            e isa SystemError || rethrow()
            rc = PL_error(
                ld, "", 0, Base.Libc.strerror(e.errnum), ERR_FILE_OPERATION,
                mk_sym(T, :set_end_of_stream), mk_sym(T, :stream), A1, e.errnum
            )
            return rc ? FTRUE : FFALSE
        end
        return FTRUE
    end
    rc = PL_error(
        ld, "", 0, "not a file", ERR_PERMISSION, mk_sym(T, :set_end_of_stream),
        mk_sym(T, :stream), A1
    )
    return rc ? FTRUE : FFALSE
end

# ── buffer and size (pl-file.c) ─────────────────────────────────────────────────────────────────

# PORT: pl-file.c fill_buffer as pl_fill_buffer1_va
# (PRED_IMPL("fill_buffer", 1, fill_buffer, 0)) — pl-file.c:5910-5928 (pin 18168e62)
# DIVERGES: `s->bufp--` is `s.bufp -= 1` on the index into `s.mem`; no lock to release.
"`fill_buffer(+Stream)`: fill the buffer of the input stream `Stream` (pl-file.c)."
function pl_fill_buffer1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    stream = PL__t0
    s = getInputStream(ld, stream, S_DONTCARE)
    if s !== nothing
        if (s.flags & SIO_NBUF) != 0
            _PL_permission_error(ld, :fill_buffer, :stream, stream)
            return FFALSE
        end

        if (s.flags & SIO_FEOF) == 0
            if S__fillbuf(s) < 0
                return streamStatus(ld, s) ? FTRUE : FFALSE      # PL_release_stream(s)
            end

            s.bufp -= 1
        end
        return streamStatus(ld, s) ? FTRUE : FFALSE              # PL_release_stream(s)
    end

    return FFALSE
end

# PORT: pl-file.c size_stream as pl_dsize_stream2_va
# (PRED_IMPL("$size_stream", 2, size_stream, 0)) — pl-file.c:6262-6279 (pin 18168e62)
# DIVERGES: `PL_get_stream_handle` is `term_stream_handle(SH_ERRORS|SH_ALIAS)`; `Ssize` knows a file's size only (see there).
"`'\$size_stream'(+Stream, -Size)`: the size in bytes of the data object `Stream` reads or writes (pl-file.c)."
function pl_dsize_stream2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    s = term_stream_handle(ld, A1, SH_ERRORS | SH_ALIAS)         # PL_get_stream_handle
    s === nothing && return FFALSE
    sz = Ssize(s)
    streamStatus(ld, s) || return FFALSE                        # PL_release_stream(s)

    sz >= 0 && return PL_unify_int64(ld, A2, Int(sz)) ? FTRUE : FFALSE

    _PL_permission_error(ld, :reposition, :stream, A1)
    return FFALSE
end

# ── pending input (pl-file.c) ───────────────────────────────────────────────────────────────────

# PORT: pl-file.c MAX_PENDING
"The most bytes `read_pending_codes/3` and `read_pending_chars/3` take from the buffer at once (pl-file.c)."
const MAX_PENDING = SIO_BUFSIZE

# PORT: pl-file.c re_buffer
# DIVERGES: `from` is an index into `buf` (a byte vector), the memory move is `copyto!` within `s.mem`.
"Put the `len` bytes of `buf` from index `from` back as the pending input of `s` (pl-file.c)."
function re_buffer(s::IOSTREAM, buf::Vector{UInt8}, from::Int, len::Int)::Nothing
    if s.bufp < s.limitp
        pending = s.limitp - s.bufp

        copyto!(s.mem, s.buffer, s.mem, s.bufp, pending)
        s.bufp = s.buffer
        s.limitp = s.bufp + pending
    else
        s.bufp = s.limitp = s.buffer
    end

    copyto!(s.mem, s.bufp, buf, from, len)
    s.limitp = s.bufp + len
    return nothing
end

# PORT: pl-file.c skip_cr
"Whether a carriage return read from the text stream `s` is dropped: a DOS newline mode (detected on the first) (pl-file.c)."
function skip_cr(s::IOSTREAM)::Bool
    if (s.flags & SIO_TEXT) != 0
        if s.newline == SIO_NL_DETECT
            s.newline = SIO_NL_DOS
            return true
        elseif s.newline == SIO_NL_DOS
            return true
        end
    end
    return false
end

# PORT: pl-file.c get_ucs2
# DIVERGES: `i` is the 1-based index of the first byte of the unit in `us`.
"The UCS-2 unit at index `i` of `us`, big or little endian (pl-file.c)."
function get_ucs2(us::Vector{UInt8}, i::Int, be::Bool)::Int
    if be
        return (Int(us[i]) << 8) + Int(us[i + 1])
    else
        return (Int(us[i + 1]) << 8) + Int(us[i])
    end
end

# ORIGINAL: pl-file.c's `allocList`, `addSmallIntList`, `addCharList`, `unifyDiffList` build the list on the global stack
# in place, with a hole for the tail; the codes are collected, then `PL_unify_text` (ENC_WCHAR units) builds the list ending
# in a fresh tail term, which is unified with `tail`.
"Unify `list` with the list of the code points `codes` (as codes, or one-character atoms if `chars`), whose end unifies with `tail`."
function unify_diff_list(
    ld::PL_local_data{T}, list::term_t, tail::term_t, codes::Vector{Int}, chars::Bool
)::Bool where {T}
    bytes = Vector{UInt8}(undef, 4 * length(codes))
    for (k, c) in enumerate(codes)
        u = UInt32(c)
        bytes[4k - 3] = UInt8(u & 0xff)
        bytes[4k - 2] = UInt8((u >> 8) & 0xff)
        bytes[4k - 1] = UInt8((u >> 16) & 0xff)
        bytes[4k] = UInt8((u >> 24) & 0xff)
    end
    text = PL_chars_t(bytes, length(codes), ENC_WCHAR, true)
    hole = PL_new_term_ref(ld)
    hole == 0 && return false
    PL_unify_text(ld, list, hole, text, chars ? PL_CHAR_LIST : PL_CODE_LIST) || return false
    return PL_unify(ld, tail, hole)
end

# PORT: pl-file.c read_pending_input
# DIVERGES: the pending bytes are copied to a `Vector{UInt8}`; the list is built by `unify_diff_list`; `ENC_ANSI` is a named
# refusal (no multibyte state in the kernel's streams); no lock to release.
"The pending input of a stream as the difference list `list`-`tail` of codes or chars (pl-file.c)."
function read_pending_input(
    ld::PL_local_data{T}, input::term_t, list::term_t, tail::term_t, chars::Bool
)::Bool where {T}
    s = getInputStream(ld, input, S_DONTCARE)
    s === nothing && return false

    buf = Vector{UInt8}(undef, MAX_PENDING)
    off0 = Stell64(s)

    if Sferror(s) != 0
        return streamStatus(ld, s)
    end

    n = Sread_pending(s, buf, MAX_PENDING, SIO_RP_NOPOS)
    n < 0 && return streamStatus(ld, s)                   # should not happen
    if n == 0                                             # end-of-file
        return streamStatus(ld, s) && PL_unify(ld, list, tail) && PL_unify_nil(ld, list)
    end
    p = s.position
    pos0 = p === nothing ? IOPOS() : IOPOS(p.byteno, p.charno, p.lineno, p.linepos, p.esc_state)

    codes = Int[]
    failed = false
    enc = s.encoding

    if enc == ENC_OCTET || enc == ENC_ISO_LATIN_1 || enc == ENC_ASCII
        for i in 1:n
            c = Int(buf[i])

            c == Int('\r') && skip_cr(s) && continue

            p !== nothing && S__fupdatefilepos_getc(s, c)

            push!(codes, c)
        end
        p !== nothing && (p.byteno = pos0.byteno + n)
    elseif enc == ENC_ANSI
        throw(
            NotPortedError{Nothing}(
                nothing, "read_pending_codes/3 on an ENC_ANSI stream", "no multibyte state in the kernel's streams"
            )
        )
    elseif enc == ENC_UTF8
        us = 1
        es = n + 1
        count = 0

        while us < es && !failed
            b0 = Int(buf[us])
            if (b0 & 0x80) == 0
                count += 1
                us += 1
            else
                ex = UTF8_FBN(b0)

                if ex >= 0
                    ec = us + ex + 1

                    if ec <= es
                        count += 1
                        us = ec
                    else                                  # incomplete multi-byte
                        break
                    end
                else
                    Sseterr(s, SIO_WARN, "Illegal multibyte Sequence")
                    failed = true
                end
            end
        end

        if !failed
            us = 1
            for _ in 1:count
                _, us, c = _PL__utf8_code_point(buf, us, es)
                c == Int('\r') && skip_cr(s) && continue
                p !== nothing && S__fupdatefilepos_getc(s, c)

                push!(codes, c)
            end
            p !== nothing && (p.byteno = pos0.byteno + (us - 1))

            re_buffer(s, buf, us, es - us)
        end
    elseif enc == ENC_UTF16BE || enc == ENC_UTF16LE
        be = enc == ENC_UTF16BE
        count = 0
        us = 1
        es = n + 1
        done = 0

        while us + 2 <= es && !failed
            c = get_ucs2(buf, us, be)
            us += 2
            if IS_UTF16_LEAD(c)
                if us + 2 <= es
                    c2 = get_ucs2(buf, us, be)

                    if IS_UTF16_TRAIL(c2)
                        count += 1
                        us += 2
                    else
                        Sseterr(s, SIO_WARN, "Illegal UTF-16 surrogate pair")
                        failed = true
                    end
                end
            else
                count += 1
            end
        end

        if !failed
            us = 1
            for _ in 1:count
                c = get_ucs2(buf, us, be)
                us += 2
                done += 2
                c == Int('\r') && skip_cr(s) && continue

                if IS_UTF16_LEAD(c)
                    c2 = get_ucs2(buf, us, be)

                    done += 2
                    us += 2
                    c = utf16_decode(c, c2)
                end

                p !== nothing && S__fupdatefilepos_getc(s, c)

                push!(codes, c)
            end

            p !== nothing && (p.byteno = pos0.byteno + done)
            re_buffer(s, buf, 1 + done, n - done)
        end
    elseif enc == ENC_WCHAR
        count = n ÷ 4

        for i in 1:count
            c = Int(buf[4i - 3]) | (Int(buf[4i - 2]) << 8) | (Int(buf[4i - 1]) << 16) | (Int(buf[4i]) << 24)

            c == Int('\r') && skip_cr(s) && continue
            p !== nothing && S__fupdatefilepos_getc(s, c)

            push!(codes, c)
        end

        done = count * 4
        p !== nothing && (p.byteno = pos0.byteno + done)
        re_buffer(s, buf, 1 + done, n - done)
    else                                                  # ENC_UNKNOWN
        error("read_pending_input: unknown encoding $enc")      # assert(0)
    end

    if !failed && unify_diff_list(ld, list, tail, codes, chars)
        return true
    end

    Sseek64(s, off0, SIO_SEEK_SET)                        # TBD: error?
    if p !== nothing
        p.byteno = pos0.byteno
        p.charno = pos0.charno
        p.lineno = pos0.lineno
        p.linepos = pos0.linepos
        p.esc_state = pos0.esc_state
    end
    return false
end

# PORT: pl-file.c read_pending_codes as pl_read_pending_codes3_va
# (PRED_IMPL("read_pending_codes", 3, read_pending_codes, 0)) — pl-file.c:3351-3356 (pin 18168e62)
"`read_pending_codes(+StreamIn, -Codes, ?Tail)`: the codes pending in the buffer of `StreamIn`, as a difference list (pl-file.c)."
function pl_read_pending_codes3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return read_pending_input(ld, PL__t0, PL__t0 + 1, PL__t0 + 2, false) ? FTRUE : FFALSE
end

# PORT: pl-file.c read_pending_chars as pl_read_pending_chars3_va
# (PRED_IMPL("read_pending_chars", 3, read_pending_chars, 0)) — pl-file.c:3358-3363 (pin 18168e62)
"`read_pending_chars(+StreamIn, -Chars, ?Tail)`: the characters pending in the buffer of `StreamIn`, as a difference list (pl-file.c)."
function pl_read_pending_chars3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return read_pending_input(ld, PL__t0, PL__t0 + 1, PL__t0 + 2, true) ? FTRUE : FFALSE
end

# ORIGINAL: the `PL_chars_t` upstream's `peek_string` fills from the stream's buffer (text.text.t = s->bufp, length in bytes):
# a copy of the pending bytes, in the stream's encoding. DIVERGES: for `ENC_WCHAR` the length is in units (upstream passes
# the byte count, which `PL_canonicalise_text` would read as units, past the buffer).
"The pending bytes of `s`'s buffer as a text not yet canonical, in `s`'s encoding."
function peek_pending_text(s::IOSTREAM)::PL_chars_t
    bytes = s.mem[s.bufp:(s.limitp - 1)]
    n = length(bytes)
    return PL_chars_t(bytes, s.encoding == ENC_WCHAR ? n ÷ 4 : n, s.encoding, false)
end

# PORT: pl-file.c peek_string as pl_peek_string3_va
# (PRED_IMPL("peek_string", 3, peek_string, 0)) — pl-file.c:3373-3425 (pin 18168e62)
# DIVERGES: the pending bytes are copied (`peek_pending_text`); no lock to release, no `PL_STRINGS_MARK`.
# DIVERGES: the pin's UTF-16 path fails its own assertion (PL_unify_text_range, canonical) or answers
# representation_error(code_point) after a read to the end: no oracle row exists; the kernel decodes UTF-16 correctly.
"`peek_string(+Stream, +Len, -String)`: `String` is the next `Len` characters of `Stream`, or all it has, without reading them (pl-file.c)."
function pl_peek_string3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2

    len = PL_get_size_ex(ld, A2)
    len === nothing && return FFALSE

    s = getInputStream(ld, A1, S_DONTCARE)
    s === nothing && return FFALSE

    while true
        if s.limitp > s.bufp
            text = peek_pending_text(s)

            PL_canonicalise_text_ex(ld, text) || return FFALSE
            if text.length >= len
                rc = PL_unify_text_range(ld, A3, text, 0, len, PL_STRING)
                return rc ? FTRUE : FFALSE
            end
        end

        if s.limitp - s.bufp == s.bufsize
            Ssetbuffer(s, nothing, s.bufsize * 2)
        end

        if S__fillbuf(s) < 0
            Sferror(s) != 0 && return streamStatus(ld, s) ? FTRUE : FFALSE

            s.flags &= ~SIO_FEOF

            text = peek_pending_text(s)
            rc = PL_canonicalise_text_ex(ld, text) && PL_unify_text(ld, A3, 0, text, PL_STRING)
            return rc ? FTRUE : FFALSE
        end
        s.bufp -= 1
    end
end

# PORT: pl-file.c copy_stream_data
# DIVERGES: `len` is 0 for no length (upstream: a NULL `term_t`); no `PL_handle_signals` every 4096 characters, no locks.
"Copy the characters of the input stream `in` to the output stream `out`, at most the integer `len` (0: all) (pl-file.c)."
function copy_stream_data(
    ld::PL_local_data{T}, in::term_t, out::term_t, len::term_t
)::Bool where {T}
    i = getInputStream(ld, in, S_DONTCARE)
    i === nothing && return false
    o = getOutputStream(ld, out, S_DONTCARE)
    o === nothing && return false

    if len == 0
        while (c = Sgetcode(i)) != EOF
            if Sputcode(c, o) < 0
                return streamStatus(ld, o)
            end
        end
    else
        n = PL_get_int64_ex(ld, len)
        n === nothing && return false

        while n > 0 && (c = Sgetcode(i)) != EOF
            n -= 1
            Sputcode(c, o) < 0 && break
        end
    end

    rc = streamStatus(ld, o)
    rc = streamStatus(ld, i) && rc

    return rc
end

# PORT: pl-file.c copy_stream_data3 as pl_copy_stream_data3_va
# (PRED_IMPL("copy_stream_data", 3, copy_stream_data3, 0)) — pl-file.c:6338-6342 (pin 18168e62)
"`copy_stream_data(+StreamIn, +StreamOut, +Len)`: copy `Len` characters from `StreamIn` to `StreamOut` (pl-file.c)."
function pl_copy_stream_data3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return copy_stream_data(ld, PL__t0, PL__t0 + 1, PL__t0 + 2) ? FTRUE : FFALSE
end

# PORT: pl-file.c copy_stream_data2 as pl_copy_stream_data2_va
# (PRED_IMPL("copy_stream_data", 2, copy_stream_data2, 0)) — pl-file.c:6344-6348 (pin 18168e62)
"`copy_stream_data(+StreamIn, +StreamOut)`: copy all characters from `StreamIn` to `StreamOut` (pl-file.c)."
function pl_copy_stream_data2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return copy_stream_data(ld, PL__t0, PL__t0 + 1, 0) ? FTRUE : FFALSE
end

# ── prompts (pl-file.c) ─────────────────────────────────────────────────────────────────────────

# PORT: pl-file.c prompt as pl_prompt2_va
# (PRED_IMPL("prompt", 2, prompt, 0)) — swipl-devel cbf4e189, src/os/pl-file.c:3735-3763
# DIVERGES: atoms are not registered (`PL_register_atom`: no atom garbage collection); `LD->prompt.current` is
# `ld.prompt_current`, set in the local data's constructor where upstream's `initIO` sets it (pl-file.c:536).
"`prompt(-Old, +New)`: unify `Old` with the prompt of the terminal read and set it to `New` (pl-file.c)."
function pl_prompt2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    PL_unify_atom(ld, A1, ld.prompt_current) || return FFALSE
    rc = PL_compare(ld, A1, A2)
    rc == 0 && return FTRUE                                 # CMP_EQUAL
    a = PL_get_atom_ex(ld, A2)
    a === nothing && return FFALSE
    ld.prompt_current = a
    return FTRUE
end

# PORT: pl-file.c prompt1
# DIVERGES: atoms are not registered (see `pl_prompt2_va`).
"Set the prompt for the first line of the next read to `prompt` (pl-file.c `prompt1(atom_t)`)."
function prompt1(ld::PL_local_data{T}, prompt::T)::Nothing where {T}
    if ld.prompt_first === nothing || sym_key(ld.prompt_first::T) != sym_key(prompt)
        ld.prompt_first = prompt
    end
    ld.prompt_first_used = false
    return nothing
end

# PORT: pl-file.c prompt1 as pl_prompt1_1_va
# (PRED_IMPL("prompt1", 1, prompt1, 0)) — pl-file.c:3778-3794
"`prompt1(+Prompt)`: the prompt of the first line of the next read; unbound `Prompt` unifies with the current one (pl-file.c)."
function pl_prompt1_1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    a = PL_get_atom(ld, A1)
    if a !== nothing
        prompt1(ld, a)
    elseif PL_is_variable(ld, A1)
        ld.prompt_first === nothing && return FFALSE
        return PL_unify_atom(ld, A1, ld.prompt_first::T) ? FTRUE : FFALSE
    else
        txt = PL_get_text(ld, A1, CVT_ALL | CVT_EXCEPTION)
        txt === nothing && return FFALSE
        PL_canonicalise_text(txt) == 1 || return FFALSE      # textToAtom(): 0
        prompt1(ld, _atom_from_text(T, _text_string(txt)))
    end
    return FTRUE
end

# PORT: pl-file.c validUserStreams
# DIVERGES: a stream slot that holds none counts as in error.
"True if the three user streams are not in an error mode (pl-file.c)."
function validUserStreams(ld::PL_local_data)::Bool
    for s in (Suser_input(ld), Suser_output(ld), Suser_error(ld))
        (s === nothing || Sferror(s) != 0) && return false
    end
    return true
end

# PORT: pl-file.c PrologPrompt
# DIVERGES: the atom is the symbol, `nothing` for upstream's 0 (the empty prompt).
"The prompt for the next read from `user_input`: `prompt1/1`'s once, else `prompt/2`'s at the start of a line, else `nothing` (pl-file.c)."
function PrologPrompt(ld::PL_local_data{T})::Union{Nothing, T} where {T}
    if !ld.prompt_first_used && ld.prompt_first !== nothing
        ld.prompt_first_used = true

        return ld.prompt_first::T
    end

    in = Suser_input(ld)
    if in !== nothing && in.position !== nothing && (in.position::IOPOS).linepos == 0
        return ld.prompt_current
    end

    return nothing                                      # ""
end

# PORT: pl-file.c PL_write_prompt
# DIVERGES: the database is an argument (the atom is written by `writeAtomToStream`); no stream lock (`getStream` is the magic check).
"Write the prompt to `user_output` where `dowrite`, flush it, and clear `prompt.next` (pl-file.c)."
function PL_write_prompt(
    gd::PL_global_data{T}, ld::PL_local_data{T}, dowrite::Bool
)::Nothing where {T}
    uo = Suser_output(ld)
    s = uo === nothing ? nothing : getStream(uo)

    if s !== nothing
        if dowrite
            a = PrologPrompt(ld)

            a === nothing || writeAtomToStream(gd, ld, s, a)
        end

        Sflush(s)
        # releaseStream(s)
    end

    ld.prompt_next = false

    return nothing
end

# ── the input context stack: the predicates (pl-file.c, "TEMPORARY I/O"); `push_input_context` and
# `pop_input_context` are LB3's (above), the stack is `ld.input_context_stack` ─────────────────────────────────

# PORT: pl-file.c push_input_context as pl_push_input_context1_va
# (PRED_IMPL("$push_input_context", 1, push_input_context, 0)) — pl-file.c:1623-1632
function pl_push_input_context1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    type = PL_get_atom_ex(ld, PL__t0)
    type === nothing && return FFALSE
    return push_input_context(ld, type) ? FTRUE : FFALSE
end

# PORT: pl-file.c pop_input_context as pl_pop_input_context0_va
# (PRED_IMPL("$pop_input_context", 0, pop_input_context, 0)) — pl-file.c:1635-1639
function pl_pop_input_context0_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return pop_input_context(ld) ? FTRUE : FFALSE
end

# PORT: pl-file.c input_context as pl_input_context1_va
# (PRED_IMPL("$input_context", 1, input_context, 0)) — pl-file.c:1647-1672
# DIVERGES: `PL_unify_term(head, PL_FUNCTOR, FUNCTOR_input4, …)` is `PL_unify_functor` then `PL_unify_arg` of each argument.
"`'\$input_context'(-List)`: the list of `input(Type, File, Line, Stream)` terms of the input context stack, the top first (pl-file.c)."
function pl_input_context1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    tail = PL_copy_term_ref(ld, A1)
    head = PL_new_term_ref(ld)
    stream = PL_new_term_ref(ld)
    arg = PL_new_term_ref(ld)
    for c in Iterators.reverse(ld.input_context_stack)
        file = c.term_file === nothing ? mk_sym(T, :-) : c.term_file::T
        line = c.term_file === nothing ? 0 : c.term_line
        PL_put_variable(ld, stream)
        PL_unify_stream_or_alias(ld, stream, c.stream::IOSTREAM) || return FFALSE   # never NULL: the streams are open from the engine's creation
        PL_unify_list(ld, tail, head, tail) || return FFALSE
        PL_unify_functor(ld, head, mk_sym(T, :input), 4) || return FFALSE
        (
            _PL_get_arg(ld, 1, head, arg) && PL_unify_atom(ld, arg, c.type) &&
            _PL_get_arg(ld, 2, head, arg) && PL_unify_atom(ld, arg, file) &&
            _PL_get_arg(ld, 3, head, arg) && PL_unify_integer(ld, arg, line) &&
            PL_unify_arg(ld, 4, head, stream)
        ) || return FFALSE
    end
    return PL_unify_nil(ld, tail) ? FTRUE : FFALSE
end

# ── flush, is_stream, $alias_stream (pl-file.c) ─────────────────────────────────────────────────

# PORT: pl-file.c ttyflush as pl_ttyflush0_va
# (PRED_IMPL("ttyflush", 0, ttyflush, 0)) — pl-file.c:3690-3702
"`ttyflush`: flush `user_output` (pl-file.c)."
function pl_ttyflush0_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    s = Suser_output(ld)
    if s !== nothing && s.magic == SIO_MAGIC                    # getStream(Suser_output)
        Sflush(s)
        return streamStatus(ld, s) ? FTRUE : FFALSE
    end
    return symbol_no_stream(ld, mk_sym(T, :user_output)) ? FTRUE : FFALSE
end

# PORT: pl-file.c is_stream as pl_is_stream1_va
# (PRED_IMPL("is_stream", 1, is_stream, 0)) — pl-file.c:5476-5487
"`is_stream(@Term)`: true if `Term` is a stream handle or the alias of an open stream (pl-file.c)."
function pl_is_stream1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    a = PL_get_atom(ld, PL__t0)
    a === nothing && return FFALSE
    return get_stream_handle(ld, a, SH_UNLOCKED) === nothing ? FFALSE : FTRUE
end

# PORT: pl-file.c dalias_stream as pl_dalias_stream2_va
# (PRED_IMPL("\$alias_stream", 2, dalias_stream, 0)) — pl-file.c:5457-5473
"`'\$alias_stream'(+Alias, -Stream)`: the stream blob the alias names (pl-file.c)."
function pl_dalias_stream2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    a = PL_get_atom_ex(ld, A1)
    a === nothing && return FFALSE
    s = get_stream_handle(ld, a, SH_UNLOCKED)
    s === nothing && return FFALSE
    s.context != 0 || return FFALSE
    return unify_stream_ref(ld, A2, s) ? FTRUE : FFALSE
end

# PORT: pl-file.c flush_output
"Flush the output stream term reference `out` names (0: the current output) (pl-file.c)."
function flush_output(ld::PL_local_data, out::term_t)::Bool
    s = getOutputStream(ld, out, S_DONTCARE)
    if s !== nothing
        Sflush(s)
        return streamStatus(ld, s)
    end
    return false
end

# PORT: pl-file.c flush_output1 as pl_flush_output1_va
# (PRED_IMPL("flush_output", 1, flush_output1, PL_FA_ISO)) — pl-file.c:5516-5521
"`flush_output(+Stream)` (pl-file.c)."
function pl_flush_output1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return flush_output(ld, PL__t0) ? FTRUE : FFALSE
end

# PORT: pl-file.c flush_output as pl_flush_output0_va
# (PRED_IMPL("flush_output", 0, flush_output, PL_FA_ISO)) — pl-file.c:5550-5555 (pin 18168e62)
"`flush_output`: flush the current output (pl-file.c)."
function pl_flush_output0_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return flush_output(ld, 0) ? FTRUE : FFALSE
end

# ── current_input/1, current_output/1, line_count/2, line_position/2, tab/1,2 (pl-file.c) ──────

# ORIGINAL: pl-file.c `is_stream_blob`'s `PL_blob_data(a, NULL, &type); type == &stream_blob`, through `_stream_ref_of`.
"Whether the term reference `t` holds a stream blob (pl-file.c `is_stream_blob`)."
function is_stream_blob(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    a = PL_get_atom(ld, t)
    a === nothing && return false
    return _stream_ref_of(ld, a) !== nothing
end

# PORT: pl-file.c current_io
# DIVERGES: `cur` is `nothing` when the current stream is unset (upstream dereferences NULL): `existence_error`.
"Unify `t` with the stream `cur`, or test a bound `t` (a stream blob or alias) against it (pl-file.c)."
function current_io(
    ld::PL_local_data{T}, t::term_t, cur::Union{Nothing, IOSTREAM}, name::Symbol
)::Bool where {T}
    cur === nothing && return no_stream(ld, 0, name)
    if PL_is_variable(ld, t)
        return PL_unify_stream(ld, t, cur)
    else
        is_stream_blob(ld, t) || return not_a_stream(ld, t, 0)
        s = term_stream_handle(ld, t, SH_ALIAS | SH_UNLOCKED)
        s === nothing && return false
        return s === cur
    end
end

# PORT: pl-file.c current_input as pl_current_input1_va
# (PRED_IMPL("current_input", 1, current_input, PL_FA_ISO)) — pl-file.c:5727-5731
"`current_input(-Stream)`: the current input stream (pl-file.c)."
function pl_current_input1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return current_io(ld, PL__t0, Scurin(ld), :current_input) ? FTRUE : FFALSE
end

# PORT: pl-file.c current_output as pl_current_output1_va
# (PRED_IMPL("current_output", 1, current_output, PL_FA_ISO)) — pl-file.c:5734-5738
"`current_output(-Stream)`: the current output stream (pl-file.c)."
function pl_current_output1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return current_io(ld, PL__t0, Scurout(ld), :current_output) ? FTRUE : FFALSE
end

# PORT: pl-file.c getStreamWithPosition
# DIVERGES: returns the stream or `nothing` (upstream: `bool` and `IOSTREAM **sp`); `PL_get_stream(stream, &s, 0)` is
# `term_stream_handle(SH_ERRORS|SH_NOPAIR)` (`PL_get_stream_from_blob`: no input or output flag asks for NOPAIR); no lock to release. `PL_get_stream`
# passes its own flags (0) to `not_a_stream`, so a non-atom argument is `domain_error(stream, X)`, not `stream_or_alias`
# (swipl 10.1.19: `line_count(1, N)`); `get_stream_handle` never reads `SH_ALIAS` for an atom's lookup.
"The stream `stream` names if it records a position, else `permission_error(property, position, Stream)` (pl-file.c)."
function getStreamWithPosition(
    ld::PL_local_data{T}, stream::term_t
)::Union{Nothing, IOSTREAM} where {T}
    s = term_stream_handle(ld, stream, SH_ERRORS | SH_NOPAIR)
    s === nothing && return nothing
    if s.position === nothing
        _PL_permission_error(ld, :property, :position, stream)     # non-ISO
        return nothing
    end
    return s
end

# PORT: pl-file.c line_count as pl_line_count2_va
# (PRED_IMPL("line_count", 2, line_count, 0)) — pl-file.c:5773-5785
"`line_count(+Stream, -Count)`: the line number of `Stream` (pl-file.c)."
function pl_line_count2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    s = getStreamWithPosition(ld, PL__t0)
    s === nothing && return FFALSE
    n = (s.position::IOPOS).lineno
    return PL_unify_integer(ld, PL__t0 + 1, n) ? FTRUE : FFALSE
end

# PORT: pl-file.c line_position as pl_line_position2_va
# (PRED_IMPL("line_position", 2, line_position, 0)) — pl-file.c:5789-5801
"`line_position(+Stream, -Position)`: the column of `Stream` (pl-file.c)."
function pl_line_position2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    s = getStreamWithPosition(ld, PL__t0)
    s === nothing && return FFALSE
    n = (s.position::IOPOS).linepos
    return PL_unify_integer(ld, PL__t0 + 1, n) ? FTRUE : FFALSE
end

# PORT: pl-file.c byte_count as pl_byte_count2_va
# (PRED_IMPL("byte_count", 2, byte_count, 0)) — pl-file.c:5782-5795 (pin 18168e62)
"`byte_count(+Stream, -Count)`: the byte position of `Stream` (pl-file.c)."
function pl_byte_count2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    s = getStreamWithPosition(ld, PL__t0)
    s === nothing && return FFALSE
    n = (s.position::IOPOS).byteno
    return PL_unify_integer(ld, PL__t0 + 1, n) ? FTRUE : FFALSE
end

# PORT: pl-file.c character_count as pl_character_count2_va
# (PRED_IMPL("character_count", 2, character_count, 0)) — pl-file.c:5798-5811 (pin 18168e62)
"`character_count(+Stream, -Count)`: the character position of `Stream` (pl-file.c)."
function pl_character_count2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    s = getStreamWithPosition(ld, PL__t0)
    s === nothing && return FFALSE
    n = (s.position::IOPOS).charno
    return PL_unify_integer(ld, PL__t0 + 1, n) ? FTRUE : FFALSE
end

# PORT: pl-file.c set_input as pl_set_input1_va
# (PRED_IMPL("set_input", 1, set_input, PL_FA_ISO)) — pl-file.c:5709-5721 (pin 18168e62)
"`set_input(+Stream)`: make `Stream` the current input (pl-file.c)."
function pl_set_input1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    s = getInputStream(ld, PL__t0, S_DONTCARE)
    if s !== nothing
        setStandardStream(ld, SNO_CURRENT_INPUT, s)
        return FTRUE
    end
    return FFALSE
end

# PORT: pl-file.c set_output as pl_set_output1_va
# (PRED_IMPL("set_output", 1, set_output, PL_FA_ISO)) — pl-file.c:5724-5736 (pin 18168e62)
"`set_output(+Stream)`: make `Stream` the current output (pl-file.c)."
function pl_set_output1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    s = getOutputStream(ld, PL__t0, S_DONTCARE)
    if s !== nothing
        setStandardStream(ld, SNO_CURRENT_OUTPUT, s)
        return FTRUE
    end
    return FFALSE
end

# PORT: pl-file.c tab
# DIVERGES: no lock (`releaseStream`).
"Write `spaces` (an integer expression) space characters to the text output stream `out` names (pl-file.c)."
function tab(ld::PL_local_data, out::term_t, spaces::term_t)::Bool
    s = getTextOutputStream(ld, out)
    s === nothing && return false
    count = PL_eval_expression_to_int64_ex(ld, spaces)
    count === nothing && return false

    while count > 0
        count -= 1
        Sputcode(Int(' '), s) < 0 && break
    end

    return streamStatus(ld, s)
end

# PORT: pl-file.c tab2 as pl_tab2_va
# (PRED_IMPL("tab", 2, tab2, 0)) — pl-file.c:3837-3841
"`tab(+Stream, +Amount)`: write `Amount` spaces to `Stream` (pl-file.c)."
function pl_tab2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return tab(ld, PL__t0, PL__t0 + 1) ? FTRUE : FFALSE
end

# PORT: pl-file.c tab1 as pl_tab1_va
# (PRED_IMPL("tab", 1, tab1, 0)) — pl-file.c:3844-3848
"`tab(+Amount)`: write `Amount` spaces to the current output (pl-file.c)."
function pl_tab1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return tab(ld, 0, PL__t0) ? FTRUE : FFALSE
end

# ── at_end_of_stream/0,1, get_code/1,2, put_code/1,2 (pl-file.c) ────────────────────────────────

# PORT: pl-file.c at_end_of_stream
# DIVERGES: no lock (`releaseStream`).
"Whether the input stream `stream` names (0: the current input) is at its end; an unbuffered stream is a permission error (pl-file.c)."
function at_end_of_stream(ld::PL_local_data{T}, stream::term_t)::Bool where {T}
    s = getInputStream(ld, stream, S_DONTCARE)
    s === nothing && return false                   # exception

    rval = Sfeof(s)

    if rval < 0
        PL_error(
            ld, "", 0, "not-buffered stream", ERR_PERMISSION, mk_sym(T, :end_of_stream),
            mk_sym(T, :stream), stream
        )
        rval = 0
    end

    rval != 0 && Sferror(s) != 0 && return streamStatus(ld, s)     # due to error

    return rval != 0
end

# PORT: pl-file.c at_end_of_stream as pl_at_end_of_stream1_va
# (PRED_IMPL("at_end_of_stream", 1, at_end_of_stream, PL_FA_ISO)) — pl-file.c:5850-5853
"`at_end_of_stream(+Stream)`: true if `Stream` is at its end (pl-file.c)."
function pl_at_end_of_stream1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return at_end_of_stream(ld, PL__t0) ? FTRUE : FFALSE
end

# PORT: pl-file.c at_end_of_stream0 as pl_at_end_of_stream0_va
# (PRED_IMPL("at_end_of_stream", 0, at_end_of_stream0, PL_FA_ISO)) — pl-file.c:5856-5859
"`at_end_of_stream`: true if the current input is at its end (pl-file.c)."
function pl_at_end_of_stream0_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return at_end_of_stream(ld, 0) ? FTRUE : FFALSE
end

# PORT: pl-file.c get_code2
# DIVERGES: `PL_get_char(chr, &c, true)` (eof accepted) is written out as in `PL_unify_char`: `-1` and `end_of_file`
# make the call fail without the type error; no lock.
function get_code2(ld::PL_local_data{T}, in::term_t, chr::term_t)::Bool where {T}
    s = getTextInputStream(ld, in)
    if s !== nothing
        c = Sgetcode(s)

        streamStatus(ld, s) || return false         # I/O error

        PL_unify_integer(ld, chr, c) && return true

        i = PL_get_integer(ld, chr)
        a = PL_get_atom(ld, chr)
        (i == -1 || (a !== nothing && sym_key(a) == sym_key(mk_sym(T, :end_of_file)))) &&
            return false
        PL_get_char(ld, chr)                        # set type-error
    end
    return false
end

# PORT: pl-file.c get_code2 as pl_get_code2_va
# (PRED_IMPL("get_code", 2, get_code2, 0)) — pl-file.c:3641-3645
"`get_code(+Stream, -Code)`: read the next character code of `Stream`; -1 at its end (pl-file.c)."
function pl_get_code2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return get_code2(ld, PL__t0, PL__t0 + 1) ? FTRUE : FFALSE
end

# PORT: pl-file.c get_code1 as pl_get_code1_va
# (PRED_IMPL("get_code", 1, get_code1, 0)) — pl-file.c:3648-3652
"`get_code(-Code)`: read the next character code of the current input (pl-file.c)."
function pl_get_code1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return get_code2(ld, 0, PL__t0) ? FTRUE : FFALSE
end

# PORT: pl-file.c put_code
# DIVERGES: no lock; the three-argument form (`ld` first) is distinct from pl-stream.jl's `put_code(c, s)`.
"Write the character code `chr` to the text output stream `stream` names (0: the current output) (pl-file.c)."
function put_code(ld::PL_local_data, stream::term_t, chr::term_t)::Bool
    c = PL_get_char(ld, chr)                        # PL_get_char(chr, &c, false)
    c === nothing && return false
    s = getTextOutputStream(ld, stream)
    s === nothing && return false

    Sputcode(c, s)

    return streamStatus(ld, s)
end

# PORT: pl-file.c put_code2 as pl_put_code2_va
# (PRED_IMPL("put_code", 2, put_code2, 0)) — pl-file.c:3447-3451
"`put_code(+Stream, +Code)`: write the character `Code` to `Stream` (pl-file.c)."
function pl_put_code2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return put_code(ld, PL__t0, PL__t0 + 1) ? FTRUE : FFALSE
end

# PORT: pl-file.c put_code1 as pl_put_code1_va
# (PRED_IMPL("put_code", 1, put_code1, 0)) — pl-file.c:3455-3459
"`put_code(+Code)`: write the character `Code` to the current output (pl-file.c)."
function pl_put_code1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return put_code(ld, 0, PL__t0) ? FTRUE : FFALSE
end

# ── character input (pl-file.c): get_char/2, peek_char/2, skip/2, get_single_char/1 ──────────────

# PORT: pl-privitf.c PL_unify_char
# DIVERGES: `how` is `:char`, `:code` or `:byte` (upstream: `PL_CHAR`, `PL_CODE`, `PL_BYTE`); `PL_get_char(chr, &c2, true)`
# is written out, as the kernel's `PL_get_char` does not take `eof` (it answers `nothing` for -1 and `end_of_file`).
# Kept in os/pl-file.jl, its only caller.
"Unify the term reference `chr` with the character `c` as `how` asks; a bound `chr` is compared (pl-privitf.c)."
function PL_unify_char(
    ld::PL_local_data{T}, chr::term_t, c::Int, how::Symbol
)::Bool where {T}
    if PL_is_variable(ld, chr)
        how === :char && return PL_unify_atom(ld, chr, codeToAtom(T, c))
        return PL_unify_integer(ld, chr, c)
    end
    i = PL_get_integer(ld, chr)
    a = PL_get_atom(ld, chr)
    c2 = if i == -1 || (a !== nothing && sym_key(a) == sym_key(mk_sym(T, :end_of_file)))
        -1                                              # eof == true
    else
        PL_get_char(ld, chr)
    end
    c2 === nothing && return false
    return c == c2
end

# PORT: pl-file.c get_char2
function get_char2(ld::PL_local_data{T}, in::term_t, chr::term_t)::Bool where {T}
    s = getTextInputStream(ld, in)
    if s !== nothing
        c = Sgetcode(s)

        streamStatus(ld, s) || return false         # I/O error

        PL_unify_atom(ld, chr, codeToAtom(T, c)) && return true     # (c == -1: ATOM_end_of_file)

        PL_get_char(ld, chr)                        # set type-error
    end
    return false
end

# PORT: pl-file.c get_char2 as pl_get_char2_va
# (PRED_IMPL("get_char", 2, get_char2, 0); the table entry has PL_FA_ISO) — pl-file.c:3676-3680
"`get_char(+Stream, -Char)`: read the next character of `Stream`; `end_of_file` at its end (pl-file.c)."
function pl_get_char2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return get_char2(ld, PL__t0, PL__t0 + 1) ? FTRUE : FFALSE
end

# PORT: pl-file.c get_char1 as pl_get_char1_va
# (PRED_IMPL("get_char", 1, get_char1, 0)) — pl-file.c:3724-3728 (pin 18168e62)
"`get_char(-Char)`: read the next character of the current input; `end_of_file` at its end (pl-file.c)."
function pl_get_char1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return get_char2(ld, 0, PL__t0) ? FTRUE : FFALSE
end

# PORT: pl-file.c peek
# DIVERGES: `how` is `:char`, `:code` or `:byte` (upstream: `PL_CHAR`, `PL_CODE`, `PL_BYTE`); `IOPOS pos = s->posbuf` is a
# field-by-field copy, as `s.posbuf` is the object `s.position` points at (`getSingleChar` does the same); no locks
# (`releaseStream`).
"Peek the next character of the input stream `stream` names and unify it with `chr` as `how` asks (pl-file.c)."
function peek(
    ld::PL_local_data{T}, stream::term_t, chr::term_t, how::Symbol
)::Bool where {T}
    s = getInputStream(ld, stream, how === :byte ? S_BINARY : S_TEXT)
    s === nothing && return false
    if (s.flags & SIO_NBUF) != 0 || (s.bufsize != 0 && s.bufsize < UNDO_SIZE)   # PL_MB_LEN_MAX
        PL_error(
            ld, "", 0, "stream is unbuffered", ERR_PERMISSION,
            mk_sym(T, :peek), mk_sym(T, :stream), stream
        )
        return false
    end
    if how === :byte
        p = s.posbuf
        oldpos = IOPOS(p.byteno, p.charno, p.lineno, p.linepos, p.esc_state)    # IOPOS pos = s->posbuf
        c = Sgetc(s)
        c != EOF && Sungetc(c, s)
        p.byteno, p.charno, p.lineno, p.linepos, p.esc_state = oldpos.byteno,
        oldpos.charno, oldpos.lineno, oldpos.linepos, oldpos.esc_state          # s->posbuf = pos
    else
        c = Speekcode(s)
    end
    Sferror(s) != 0 && return streamStatus(ld, s)
    return PL_unify_char(ld, chr, c, how)
end

# PORT: pl-file.c peek_char2 as pl_peek_char2_va
# (PRED_IMPL("peek_char", 2, peek_char2, 0); the table entry has PL_FA_ISO) — pl-file.c:5954-5958
"`peek_char(+Stream, -Char)`: the next character of `Stream` without reading it (pl-file.c)."
function pl_peek_char2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return peek(ld, PL__t0, PL__t0 + 1, :char) ? FTRUE : FFALSE
end

# PORT: pl-file.c peek_char1 as pl_peek_char1_va
# (PRED_IMPL("peek_char", 1, peek_char1, 0)) — pl-file.c:6002-6006 (pin 18168e62)
"`peek_char(-Char)`: the next character of the current input without reading it (pl-file.c)."
function pl_peek_char1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return peek(ld, 0, PL__t0, :char) ? FTRUE : FFALSE
end

# PORT: pl-file.c peek_code2 as pl_peek_code2_va
# (PRED_IMPL("peek_code", 2, peek_code2, 0)) — pl-file.c:5981-5985 (pin 18168e62)
"`peek_code(+Stream, -Code)`: the next character code of `Stream` without reading it (pl-file.c)."
function pl_peek_code2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return peek(ld, PL__t0, PL__t0 + 1, :code) ? FTRUE : FFALSE
end

# PORT: pl-file.c peek_code1 as pl_peek_code1_va
# (PRED_IMPL("peek_code", 1, peek_code1, 0)) — pl-file.c:5988-5992 (pin 18168e62)
"`peek_code(-Code)`: the next character code of the current input without reading it (pl-file.c)."
function pl_peek_code1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return peek(ld, 0, PL__t0, :code) ? FTRUE : FFALSE
end

# PORT: pl-file.c peek_byte2 as pl_peek_byte2_va
# (PRED_IMPL("peek_byte", 2, peek_byte2, 0)) — pl-file.c:5967-5971 (pin 18168e62)
"`peek_byte(+Stream, -Byte)`: the next byte of the binary stream `Stream` without reading it (pl-file.c)."
function pl_peek_byte2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return peek(ld, PL__t0, PL__t0 + 1, :byte) ? FTRUE : FFALSE
end

# PORT: pl-file.c peek_byte1 as pl_peek_byte1_va
# (PRED_IMPL("peek_byte", 1, peek_byte1, 0)) — pl-file.c:5974-5978 (pin 18168e62)
"`peek_byte(-Byte)`: the next byte of the current (binary) input without reading it (pl-file.c)."
function pl_peek_byte1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return peek(ld, 0, PL__t0, :byte) ? FTRUE : FFALSE
end

# PORT: pl-file.c skip
function skip(ld::PL_local_data, in::term_t, chr::term_t)::Bool
    c = PL_get_char(ld, chr)                        # PL_get_char(chr, &c, false)
    c === nothing && return false
    s = getTextInputStream(ld, in)
    s === nothing && return false

    while true
        r = Sgetcode(s)
        (r == c || r == EOF) && break
    end

    return streamStatus(ld, s)
end

# PORT: pl-file.c skip2 as pl_skip2_va
# (PRED_IMPL("skip", 2, skip2, 0)) — pl-file.c:3549-3553
"`skip(+Stream, +Code)`: read `Stream` up to and including `Code` (pl-file.c)."
function pl_skip2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return skip(ld, PL__t0, PL__t0 + 1) ? FTRUE : FFALSE
end

# PORT: pl-file.c skip1 as pl_skip1_va
# (PRED_IMPL("skip", 1, skip1, 0)) — pl-file.c:3582-3587 (pin 18168e62)
"`skip(+Code)`: read the current input up to and including `Code` (pl-file.c)."
function pl_skip1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return skip(ld, 0, PL__t0) ? FTRUE : FFALSE
end

# PORT: pl-file.c get_nonblank
# DIVERGES: no lock (`releaseStream`).
"Read the next non-blank character code of the text input stream `in` names (0: the current input) and unify it with `chr`; -1 at the end (pl-file.c)."
function get_nonblank(ld::PL_local_data, in::term_t, chr::term_t)::Bool
    s = getTextInputStream(ld, in)
    if s !== nothing
        while true
            c = Sgetcode(s)

            if c == EOF
                PL_unify_integer(ld, chr, -1) || return false
                return streamStatus(ld, s)
            end

            isBlankW(c) || return PL_unify_integer(ld, chr, c)
        end
    end

    return false
end

# PORT: pl-file.c get1 as pl_get1_va
# (PRED_IMPL("get", 1, get1, 0)) — pl-file.c:3547-3552 (pin 18168e62)
"`get(-Code)`: the next non-blank character code of the current input (pl-file.c)."
function pl_get1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return get_nonblank(ld, 0, PL__t0) ? FTRUE : FFALSE
end

# PORT: pl-file.c get2 as pl_get2_va
# (PRED_IMPL("get", 2, get2, 0)) — pl-file.c:3555-3560 (pin 18168e62)
"`get(+Stream, -Code)`: the next non-blank character code of `Stream` (pl-file.c)."
function pl_get2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return get_nonblank(ld, PL__t0, PL__t0 + 1) ? FTRUE : FFALSE
end

# PORT: pl-file.c put2 as pl_put2_va
# (PRED_IMPL("put", 2, put2, 0)) — pl-file.c:3504-3509 (pin 18168e62)
"`put(+Stream, +Char)`: Edinburgh name of `put_code/2` (pl-file.c)."
function pl_put2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return put_code(ld, PL__t0, PL__t0 + 1) ? FTRUE : FFALSE
end

# PORT: pl-file.c put1 as pl_put1_va
# (PRED_IMPL("put", 1, put1, 0)) — pl-file.c:3512-3517 (pin 18168e62)
"`put(+Char)`: Edinburgh name of `put_code/1` (pl-file.c)."
function pl_put1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return put_code(ld, 0, PL__t0) ? FTRUE : FFALSE
end

# PORT: pl-file.c put_byte
# DIVERGES: no lock; the three-argument form (`ld` first) is distinct from pl-stream.jl's `put_byte(c, s)`
# (pl-stream.c put_byte), as `put_code` is from `put_code(c, s)`.
"Write the byte `byte` to the binary output stream `stream` names (0: the current output) (pl-file.c)."
function put_byte(ld::PL_local_data{T}, stream::term_t, byte::term_t)::Bool where {T}
    c = PL_get_integer(ld, byte)
    if c === nothing || c < 0 || c > 255
        PL_error(ld, ERR_TYPE, mk_sym(T, :byte), byte)
        return false
    end
    s = getOutputStream(ld, stream, S_BINARY)       # getBinaryOutputStream
    s === nothing && return false

    Sputc(c, s)

    return streamStatus(ld, s)
end

# PORT: pl-file.c put_byte2 as pl_put_byte2_va
# (PRED_IMPL("put_byte", 2, put_byte2, 0); the table entry has PL_FA_ISO) — pl-file.c:3455-3460 (pin 18168e62)
"`put_byte(+Stream, +Byte)`: write a byte to the binary stream `Stream` (pl-file.c)."
function pl_put_byte2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return put_byte(ld, PL__t0, PL__t0 + 1) ? FTRUE : FFALSE
end

# PORT: pl-file.c put_byte1 as pl_put_byte1_va
# (PRED_IMPL("put_byte", 1, put_byte1, 0); the table entry has PL_FA_ISO) — pl-file.c:3463-3468 (pin 18168e62)
"`put_byte(+Byte)`: write a byte to the current (binary) output (pl-file.c)."
function pl_put_byte1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return put_byte(ld, 0, PL__t0) ? FTRUE : FFALSE
end

# PORT: pl-file.c get_byte2
# DIVERGES: `PL_get_char(chr, &c, true)` (eof accepted) is written out as in `get_code2`: `-1` and `end_of_file`
# make the call fail without the type error; no lock.
"Read the next byte of the binary input stream `in` names (0: the current input) and unify it with `chr`; -1 at the end (pl-file.c)."
function get_byte2(ld::PL_local_data{T}, in::term_t, chr::term_t)::Bool where {T}
    s = getInputStream(ld, in, S_BINARY)            # getBinaryInputStream
    if s !== nothing
        c = Sgetc(s)

        PL_unify_integer(ld, chr, c) && return streamStatus(ld, s)

        Sferror(s) != 0 && return streamStatus(ld, s)

        i = PL_get_integer(ld, chr)
        a = PL_get_atom(ld, chr)
        (i == -1 || (a !== nothing && sym_key(a) == sym_key(mk_sym(T, :end_of_file)))) &&
            return false
        PL_get_char(ld, chr)                        # set type-error
    end
    return false
end

# PORT: pl-file.c get_byte2 as pl_get_byte2_va
# (PRED_IMPL("get_byte", 2, get_byte2, 0); the table entry has PL_FA_ISO) — pl-file.c:3645-3650 (pin 18168e62)
"`get_byte(+Stream, -Byte)`: read the next byte of the binary stream `Stream`; -1 at its end (pl-file.c)."
function pl_get_byte2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return get_byte2(ld, PL__t0, PL__t0 + 1) ? FTRUE : FFALSE
end

# PORT: pl-file.c get_byte1 as pl_get_byte1_va
# (PRED_IMPL("get_byte", 1, get_byte1, 0); the table entry has PL_FA_ISO) — pl-file.c:3653-3658 (pin 18168e62)
"`get_byte(-Byte)`: read the next byte of the current (binary) input (pl-file.c)."
function pl_get_byte1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return get_byte2(ld, 0, PL__t0) ? FTRUE : FFALSE
end

# PORT: pl-file.c Sgetcode_intr
# DIVERGES: no `EINTR` loop (a Julia read is not interrupted by a signal): one `Sgetcode`, then `Sclearerr`.
function Sgetcode_intr(s::IOSTREAM)::Int
    c = Sgetcode(s)
    Sclearerr(s)
    return c
end

# PORT: pl-file.c getSingleChar
# DIVERGES: no terminal modes (`PushTty`/`PopTty` with `TTY_RAW`: no ttys, see pl-read.jl's `PushTty` note), no
# `suspendTrace`, no `Slock`/`Sunlock`; `signals` is accepted for the signature and unused (no signal handling
# in the loop). Read from a terminal this gives a line-buffered answer, not a raw key.
"Read one character from `stream` without echo (pl-file.c): -1 at the end of the file or for ^D and ^Z."
function getSingleChar(ld::PL_local_data, stream::IOSTREAM, signals::Bool)::Int
    Sflush(stream)

    if !truePrologFlag(ld, PLFLAG_TTY_CONTROL)
        c2 = Sgetcode_intr(stream)
        while c2 == Int(' ') || c2 == Int('\t')     # skip blanks
            c2 = Sgetcode_intr(stream)
        end
        c = c2
        while c2 != EOF && c2 != Int('\n')          # read upto newline
            c2 = Sgetcode_intr(stream)
        end
    else
        if stream.position !== nothing
            p = stream.position
            oldpos = IOPOS(p.byteno, p.charno, p.lineno, p.linepos, p.esc_state)   # IOPOS oldpos = *stream->position
            c = Sgetcode_intr(stream)
            p.byteno, p.charno, p.lineno, p.linepos, p.esc_state = oldpos.byteno,
            oldpos.charno, oldpos.lineno, oldpos.linepos,
            oldpos.esc_state
        else
            c = Sgetcode_intr(stream)
        end
    end

    (c == 4 || c == 26) && (c = -1)                 # should ask the terminal!

    return c
end

# PORT: pl-file.c get_single_char as pl_get_single_char1_va
# (PRED_IMPL("get_single_char", 1, get_single_char, 0)) — pl-file.c:3557-3580
"`get_single_char(-Code)`: one character from `user_input` without waiting for a newline; -1 at the end (pl-file.c)."
function pl_get_single_char1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    s = Suser_input(ld)
    (s === nothing || s.magic != SIO_MAGIC) &&
        return symbol_no_stream(ld, mk_sym(T, :user_input)) ? FTRUE : FFALSE

    c = getSingleChar(ld, s, true)
    if c == EOF
        PL_exception(ld, 0) != 0 && return FFALSE
        PL_unify_integer(ld, PL__t0, -1)
        return streamStatus(ld, s) ? FTRUE : FFALSE
    end

    return PL_unify_integer(ld, PL__t0, c) ? FTRUE : FFALSE
end

# ── $stream_property/2, $stream_properties/2, $streams_properties/2 (pl-file.c STREAM-PROPERTY) ──

# PORT: pl-file.c PL_encoding_to_atom
# DIVERGES: the first name of `encoding_names` that has `enc` (upstream: the first of its table); `nothing`
# is upstream's NULL_ATOM, for `ENC_UNKNOWN`.
"The atom naming the encoding `enc`, or `nothing` (pl-file.c)."
function PL_encoding_to_atom(::Type{T}, enc::IOENC)::Union{Nothing, T} where {T}
    for (n, e) in encoding_names
        e == enc && return mk_sym(T, n)
    end
    return nothing
end

# PORT: pl-prologflag.c unicode_atoms_to_atom
# DIVERGES: `nothing` is upstream's NULL_ATOM; lives here with its one caller (`stream_unicode_atoms_prop`).
"The atom naming the unicode_atoms mode `m` (pl-prologflag.c)."
function unicode_atoms_to_atom(::Type{T}, m::Sunicode_atoms_t)::Union{Nothing, T} where {T}
    m == S_UATOMS_ACCEPT && return mk_sym(T, :accept)
    m == S_UATOMS_NFC && return mk_sym(T, :nfc)
    m == S_UATOMS_ERROR && return mk_sym(T, :error)
    m == S_UATOMS_REJECT && return mk_sym(T, :reject)
    return nothing
end

# PORT: pl-file.c term_stream_handle
"The stream the term `t` names, as `flags` (`SH_*`) ask, or `nothing` with the error raised (pl-file.c)."
function term_stream_handle(
    ld::PL_local_data{T}, t::term_t, flags::Int
)::Union{Nothing, IOSTREAM} where {T}
    a = PL_get_atom(ld, t)
    if a === nothing
        not_a_stream(ld, t, flags)
        return nothing
    end
    return get_stream_handle(ld, a, flags)
end

# ORIGINAL: pl-fli.c `PL_put_functor`, which the Julia FLI has not: a fresh variable, then `PL_unify_functor`.
"Put the compound `name/arity` of fresh arguments into the term reference `t` (pl-fli.c `PL_put_functor`)."
function _put_functor(
    ld::PL_local_data{T}, t::term_t, name::Symbol, arity::Int
)::Bool where {T}
    PL_put_variable(ld, t)
    return PL_unify_functor(ld, t, mk_sym(T, name), arity)
end

# ORIGINAL: unify the term `t` with the atom whose text is `name`.
function _unify_sym(ld::PL_local_data{T}, t::term_t, name::Symbol)::Bool where {T}
    return PL_unify_atom(ld, t, mk_sym(T, name))
end

# PORT: pl-file.c stream_file_name_propery
# DIVERGES: no `downstream` chain (the kernel has no filter or pair streams): only `s`; the name is the
# database's `stream_filenames` (see `fileNameStream`).
"`file_name(Name)` of `s` (pl-file.c)."
function stream_file_name_propery(
    ld::PL_local_data{T}, s::IOSTREAM, prop::term_t
)::Bool where {T}
    if s.magic == SIO_MAGIC && s.context != 0
        name = fileNameStream(_query_gd(ld), s)
        name === nothing || return PL_unify_atom(ld, prop, name)
    end
    return false
end

# PORT: pl-file.c stream_mode_property
"`mode(Mode)` of `s` (pl-file.c)."
function stream_mode_property(ld::PL_local_data, s::IOSTREAM, prop::term_t)::Bool
    if (s.flags & SIO_INPUT) != 0
        mode = :read
    elseif (s.flags & SIO_APPEND) != 0
        mode = :append
    elseif (s.flags & SIO_UPDATE) != 0
        mode = :update
    else
        mode = :write
    end
    return _unify_sym(ld, prop, mode)
end

# PORT: pl-file.c stream_input_prop
"`input` holds for an input stream (pl-file.c)."
stream_input_prop(ld::PL_local_data, s::IOSTREAM)::Bool = (s.flags & SIO_INPUT) != 0

# PORT: pl-file.c stream_output_prop
"`output` holds for an output stream (pl-file.c)."
stream_output_prop(ld::PL_local_data, s::IOSTREAM)::Bool = (s.flags & SIO_OUTPUT) != 0

# PORT: pl-file.c stream_alias_prop
# Incomplete upstream as well: should be non-deterministic if the stream has multiple aliases.
"`alias(Alias)` of `s`: with a bound atom, whether it is an alias; else the standard name or the first alias (pl-file.c)."
function stream_alias_prop(ld::PL_local_data{T}, s::IOSTREAM, prop::term_t)::Bool where {T}
    (s.magic != SIO_MAGIC || s.context == 0) && return false
    names = get(_query_gd(ld).stream_alias_names, s.context, nothing)

    name = PL_get_atom(ld, prop)
    if name !== nothing
        if names !== nothing
            for a in names
                sym_key(a) == sym_key(name) && return true
            end
        end
        i = standardStreamIndexFromName(ld, name)
        return i >= 0 && i < 6 && s === ld.IO_streams[i + 1]
    end

    i = standardStreamIndexFromStream(ld, s)
    i >= 0 && i < 3 && return _unify_sym(ld, prop, standardStreams[i + 1])
    names !== nothing && !isempty(names) && return PL_unify_atom(ld, prop, names[1])

    return false
end

# PORT: pl-file.c stream_position_prop
# DIVERGES: `PL_unify_term(prop, PL_FUNCTOR, FUNCTOR_dstream_position4, …)` is `PL_unify_functor` then
# `PL_unify_int64` of each argument.
"`position(Pos)` of `s`: `'\$stream_position'(Char, Line, LinePos, Byte)` (pl-file.c)."
function stream_position_prop(
    ld::PL_local_data{T}, s::IOSTREAM, prop::term_t
)::Bool where {T}
    if s.magic == SIO_MAGIC && s.position !== nothing
        pos = s.position::IOPOS
        a = PL_new_term_ref(ld)
        PL_unify_functor(ld, prop, mk_sym(T, Symbol("\$stream_position")), 4) ||
            return false
        rc = (
            _PL_get_arg(ld, 1, prop, a) && PL_unify_int64(ld, a, pos.charno) &&
            _PL_get_arg(ld, 2, prop, a) && PL_unify_int64(ld, a, pos.lineno) &&
            _PL_get_arg(ld, 3, prop, a) && PL_unify_int64(ld, a, pos.linepos) &&
            _PL_get_arg(ld, 4, prop, a) && PL_unify_int64(ld, a, pos.byteno)
        )
        PL_reset_term_refs(ld, a)
        return rc
    end
    return false
end

# PORT: pl-file.c stream_end_of_stream_prop
"`end_of_stream(E)` of an input stream: `not`, `at` or `past` (pl-file.c)."
function stream_end_of_stream_prop(ld::PL_local_data, s::IOSTREAM, prop::term_t)::Bool
    if s.magic == SIO_MAGIC && (s.flags & SIO_INPUT) != 0
        if (s.flags & SIO_FEOF2) != 0
            val = :past
        elseif (s.flags & SIO_FEOF) != 0
            val = :at
        else
            val = :not
        end
        return _unify_sym(ld, prop, val)
    end
    return false
end

# PORT: pl-file.c stream_error_prop
"`error(Bool)` of `s`: whether the stream is in error (pl-file.c)."
function stream_error_prop(ld::PL_local_data, s::IOSTREAM, prop::term_t)::Bool
    s.magic == SIO_MAGIC && return PL_unify_bool(ld, prop, Sferror(s) == 1)
    return false
end

# PORT: pl-file.c stream_eof_action_prop
"`eof_action(Action)` of `s` (pl-file.c)."
function stream_eof_action_prop(ld::PL_local_data, s::IOSTREAM, prop::term_t)::Bool
    if (s.flags & SIO_NOFEOF) != 0
        val = :reset
    elseif (s.flags & SIO_FEOF2ERR) != 0
        val = :error
    else
        val = :eof_code
    end
    return _unify_sym(ld, prop, val)
end

# PORT: pl-file.c stream_reposition_prop
# DIVERGES: the stream layer has no `seek`/`control` function pair and no file descriptor to `fstat`: a stream over
# a file (a Julia `IOStream`) stands in for "has a seek function and `S_ISREG(fstat(fd))`", every other stream
# (memory, string, terminal, pipe) is `false` (upstream: the same for a pipe or tty, a memory file has no fd).
"`reposition(Bool)` of `s`: whether it can be repositioned (pl-file.c)."
function stream_reposition_prop(ld::PL_local_data, s::IOSTREAM, prop::term_t)::Bool
    val = false
    if s.magic == SIO_MAGIC
        h = s.handle
        val = s.functions == Siofunctions && h isa Sjulia_io && h.io isa IOStream
    end
    return PL_unify_bool(ld, prop, val)
end

# PORT: pl-file.c stream_close_on_abort_prop
"`close_on_abort(Bool)` of `s` (pl-file.c)."
stream_close_on_abort_prop(ld::PL_local_data, s::IOSTREAM, prop::term_t)::Bool =
    PL_unify_bool_ex(ld, prop, (s.flags & SIO_NOCLOSE) == 0)

# PORT: pl-file.c stream_type_prop
"`type(Type)` of `s`: `text` or `binary` (pl-file.c)."
stream_type_prop(ld::PL_local_data, s::IOSTREAM, prop::term_t)::Bool =
    _unify_sym(ld, prop, (s.flags & SIO_TEXT) != 0 ? :text : :binary)

# The file descriptor of `s` as `Sfileno` (pl-stream.c) gives it, for the process's standard streams only: 0 for
# `Sinput`, 1 for `Soutput`, 2 for `Serror` (`S__iob`), -1 for every other stream. ORIGINAL: no `fileno` field in
# the stream (FILENO1; a struct change was not taken), so the standard streams are recognised as `closeStream` does
# (`isSinput`, `isSoutputOrSerror`, the `SIO_STATIC` flag) and told apart by the slot of `ld` they are bound to
# (the stream in `user_error`'s slot alone is `Serror`, in `user_output`'s alone `Soutput`); one in both or
# neither slot (aliased away) falls back on the flag it was made with, `SIO_NBUF` for `Serror` (`set_stream(buffer(..))`
# can change that flag, which is why the slots come first).
function _std_fileno(ld::PL_local_data, s::IOSTREAM)::Int
    isSinput(s) && return 0
    isSoutputOrSerror(s) || return -1
    in_err = (Suser_error(ld) === s)::Bool
    in_out = (Suser_output(ld) === s)::Bool
    in_err != in_out && return in_err ? 2 : 1
    return (s.flags & SIO_NBUF) != 0 ? 2 : 1
end

# PORT: pl-file.c stream_file_no_prop
# DIVERGES (representation): upstream answers `Sfileno(s)` when it is >= 0 (pl-file.c:4996-5005), the descriptor
# cached in the stream by `Snew`; the stream layer holds a Julia IO, not an OS file descriptor, so the answer is the
# descriptor of the three standard streams (`_std_fileno`: 0, 1, 2) and `false` for every other stream (FILENO1: the
# remaining representation difference; a file stream has no descriptor here, swipl's is a number >= 3).
"`file_no(Fd)` of `s`: 0, 1 or 2 for a standard stream, no answer for any other (pl-file.c)."
function stream_file_no_prop(ld::PL_local_data, s::IOSTREAM, prop::term_t)::Bool
    fd = _std_fileno(ld, s)::Int
    fd >= 0 && return PL_unify_integer(ld, prop, fd)
    return false
end

# PORT: pl-file.c stream_tty_prop
"`tty(true)` when `s` is a terminal (pl-file.c)."
function stream_tty_prop(ld::PL_local_data, s::IOSTREAM, prop::term_t)::Bool
    (s.flags & SIO_ISATTY) != 0 && return PL_unify_bool_ex(ld, prop, true)
    return false
end

# PORT: pl-file.c stream_bom_prop
"`bom(true)` when a byte order mark was detected or written (pl-file.c)."
function stream_bom_prop(ld::PL_local_data, s::IOSTREAM, prop::term_t)::Bool
    (s.flags & SIO_BOM) != 0 && return PL_unify_bool_ex(ld, prop, true)
    return false
end

# PORT: pl-file.c stream_newline_prop
"`newline(Mode)` of `s`: `posix` or `dos` (pl-file.c)."
function stream_newline_prop(ld::PL_local_data, s::IOSTREAM, prop::term_t)::Bool
    (s.newline == SIO_NL_POSIX || s.newline == SIO_NL_DETECT) &&
        return _unify_sym(ld, prop, :posix)
    s.newline == SIO_NL_DOS && return _unify_sym(ld, prop, :dos)
    return false
end

# PORT: pl-file.c stream_encoding_prop
"`encoding(Enc)` of `s` (pl-file.c)."
function stream_encoding_prop(
    ld::PL_local_data{T}, s::IOSTREAM, prop::term_t
)::Bool where {T}
    ename = PL_encoding_to_atom(T, s.encoding)
    ename === nothing || return PL_unify_atom(ld, prop, ename)
    return false
end

# PORT: pl-file.c stream_unicode_atoms_prop
"`unicode_atoms(Mode)` of `s` (pl-file.c)."
function stream_unicode_atoms_prop(
    ld::PL_local_data{T}, s::IOSTREAM, prop::term_t
)::Bool where {T}
    a = unicode_atoms_to_atom(T, s.unicode_atoms)
    a === nothing || return PL_unify_atom(ld, prop, a)
    return false
end

# PORT: pl-file.c stream_locale_prop
# DIVERGES (representation): upstream unifies `unifyLocale(prop, s->locale, true)` when the stream has a locale
# (pl-file.c:5069-5076); the stream layer has no `locale` field (`Ssetlocale` is left to the locale step), so
# the answer is `false`.
"`locale(Locale)` of `s` (pl-file.c)."
stream_locale_prop(ld::PL_local_data, s::IOSTREAM, prop::term_t)::Bool = false

# PORT: pl-file.c stream_reperror_prop
"`representation_errors(Mode)` of `s`: `xml`, `prolog`, `unicode` or `error` (pl-file.c)."
function stream_reperror_prop(ld::PL_local_data, s::IOSTREAM, prop::term_t)::Bool
    if (s.flags & SIO_REPXML) != 0
        a = :xml
    elseif (s.flags & SIO_REPPL) != 0
        a = :prolog
    elseif (s.flags & SIO_REPPLU) != 0
        a = :unicode
    else
        a = :error
    end
    return _unify_sym(ld, prop, a)
end

# PORT: pl-file.c stream_writeerror_prop
"`write_errors(Mode)` of `s`: `ignore` or `error` (pl-file.c)."
stream_writeerror_prop(ld::PL_local_data, s::IOSTREAM, prop::term_t)::Bool =
    _unify_sym(ld, prop, (s.flags & SIO_NOERROR) != 0 ? :ignore : :error)

# PORT: pl-file.c stream_buffer_prop
"`buffer(Mode)` of `s`: `full`, `line` or `false` (pl-file.c)."
function stream_buffer_prop(ld::PL_local_data, s::IOSTREAM, prop::term_t)::Bool
    if (s.flags & SIO_FBUF) != 0
        b = :full
    elseif (s.flags & SIO_LBUF) != 0
        b = :line
    else                                            # if ( s->flags & SIO_NBUF )
        b = Symbol("false")
    end
    return _unify_sym(ld, prop, b)
end

# PORT: pl-file.c stream_buffer_size_prop
"`buffer_size(Size)` of a buffered stream (pl-file.c)."
function stream_buffer_size_prop(ld::PL_local_data, s::IOSTREAM, prop::term_t)::Bool
    (s.flags & SIO_NBUF) != 0 && return false
    size = s.bufsize == 0 ? SIO_BUFSIZE : s.bufsize
    return PL_unify_integer(ld, prop, size)
end

# PORT: pl-file.c stream_timeout_prop
# DIVERGES (representation): the stream layer has no `timeout` field (`Sset_timeout` is left to the
# stream layer's own step; upstream pl-file.c:5141-5148 reads `s->timeout`, `-1` for none): no stream here can
# time out, which is what `infinite` says.
"`timeout(Time)` of `s`: `infinite` (pl-file.c)."
stream_timeout_prop(ld::PL_local_data, s::IOSTREAM, prop::term_t)::Bool =
    _unify_sym(ld, prop, :infinite)

# PORT: pl-file.c stream_nlink_prop
# DIVERGES (representation): upstream is `fstat(Sfileno(s)).st_nlink` (pl-file.c:5151-5165); no `fstat` here, even
# for a standard stream (see `stream_file_no_prop`): `false`.
"`nlink(Count)` of `s` (pl-file.c)."
stream_nlink_prop(ld::PL_local_data, s::IOSTREAM, prop::term_t)::Bool = false

# PORT: pl-file.c stream_close_on_exec_prop
# DIVERGES (representation): upstream is `fcntl(fd, F_GETFD)` (pl-file.c:5167-5199); no `fcntl` here, even for a
# standard stream (see `stream_file_no_prop`): `false`.
"`close_on_exec(Bool)` of `s` (pl-file.c)."
stream_close_on_exec_prop(ld::PL_local_data, s::IOSTREAM, prop::term_t)::Bool = false

# PORT: pl-file.c sprop
# DIVERGES: upstream's `functor` is the name and arity; its `function`/`function0` pointers are not held (a
# field of an abstract function type is no concrete field): `_call_stream_property` picks the function by the
# name, in the order of `sprop_list`.
"A stream property: its name and arity (pl-file.c `sprop`)."
struct sprop
    name::Symbol
    arity::Int
end

# PORT: pl-file.c sprop_list
"The stream properties, in upstream's order (pl-file.c)."
const sprop_list = (
    sprop(:file_name, 1),
    sprop(:mode, 1),
    sprop(:input, 0),
    sprop(:output, 0),
    sprop(:alias, 1),
    sprop(:position, 1),
    sprop(:end_of_stream, 1),
    sprop(:error, 1),
    sprop(:eof_action, 1),
    sprop(:reposition, 1),
    sprop(:type, 1),
    sprop(:file_no, 1),
    sprop(:buffer, 1),
    sprop(:buffer_size, 1),
    sprop(:close_on_abort, 1),
    sprop(:tty, 1),
    sprop(:encoding, 1),
    sprop(:unicode_atoms, 1),
    sprop(:locale, 1),
    sprop(:bom, 1),
    sprop(:newline, 1),
    sprop(:representation_errors, 1),
    sprop(:write_errors, 1),
    sprop(:timeout, 1),
    sprop(:nlink, 1),
    sprop(:close_on_exec, 1)
)

# PORT: pl-file.c get_stream_property_def
"The property definition of the functor of term `t`, or `nothing` (pl-file.c)."
function get_stream_property_def(ld::PL_local_data, t::term_t)::Union{Nothing, sprop}
    f = PL_get_functor(ld, t)
    f === nothing && return nothing
    name, arity = f
    (kind(name) === SYM && !is_reserved_symbol(name) && !is_blob(name)) || return nothing
    nm = Symbol(sym_text(name))
    for p in sprop_list
        p.name === nm && p.arity == arity && return p
    end
    return nothing
end

# ORIGINAL: upstream's `switch(arityFunctor(p->functor))` that calls the property's function: the arity-0
# function on `s`, the arity-1 function on `s` and `a1`, the argument of the property term.
function _call_stream_property(
    ld::PL_local_data, s::IOSTREAM, p::sprop, a1::term_t
)::Bool
    n = p.name
    n === :file_name && return stream_file_name_propery(ld, s, a1)::Bool
    n === :mode && return stream_mode_property(ld, s, a1)::Bool
    n === :input && return stream_input_prop(ld, s)::Bool
    n === :output && return stream_output_prop(ld, s)::Bool
    n === :alias && return stream_alias_prop(ld, s, a1)::Bool
    n === :position && return stream_position_prop(ld, s, a1)::Bool
    n === :end_of_stream && return stream_end_of_stream_prop(ld, s, a1)::Bool
    n === :error && return stream_error_prop(ld, s, a1)::Bool
    n === :eof_action && return stream_eof_action_prop(ld, s, a1)::Bool
    n === :reposition && return stream_reposition_prop(ld, s, a1)::Bool
    n === :type && return stream_type_prop(ld, s, a1)::Bool
    n === :file_no && return stream_file_no_prop(ld, s, a1)::Bool
    n === :buffer && return stream_buffer_prop(ld, s, a1)::Bool
    n === :buffer_size && return stream_buffer_size_prop(ld, s, a1)::Bool
    n === :close_on_abort && return stream_close_on_abort_prop(ld, s, a1)::Bool
    n === :tty && return stream_tty_prop(ld, s, a1)::Bool
    n === :encoding && return stream_encoding_prop(ld, s, a1)::Bool
    n === :unicode_atoms && return stream_unicode_atoms_prop(ld, s, a1)::Bool
    n === :locale && return stream_locale_prop(ld, s, a1)::Bool
    n === :bom && return stream_bom_prop(ld, s, a1)::Bool
    n === :newline && return stream_newline_prop(ld, s, a1)::Bool
    n === :representation_errors && return stream_reperror_prop(ld, s, a1)::Bool
    n === :write_errors && return stream_writeerror_prop(ld, s, a1)::Bool
    n === :timeout && return stream_timeout_prop(ld, s, a1)::Bool
    n === :nlink && return stream_nlink_prop(ld, s, a1)::Bool
    n === :close_on_exec && return stream_close_on_exec_prop(ld, s, a1)::Bool
    return false
end

# PORT: pl-file.c dstream_property as pl_dstream_property2_va
# (PRED_IMPL("\$stream_property", 2, dstream_property, 0)) — pl-file.c:5265-5300
# DIVERGES: no `PL_LOCK(L_FILE)` (no threads).
"`'\$stream_property'(+Stream, +Property)`: the property of the stream, the property's argument unified (pl-file.c)."
function pl_dstream_property2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    p = get_stream_property_def(ld, A2)
    p === nothing && return FFALSE
    s = term_stream_handle(ld, A1, SH_ERRORS | SH_UNLOCKED)
    s === nothing && return FFALSE
    a1 = PL_new_term_ref(ld)
    p.arity == 0 || _PL_get_arg(ld, 1, A2, a1)
    return _call_stream_property(ld, s, p, a1) ? FTRUE : FFALSE
end

# PORT: pl-file.c unify_stream_property_list
"Unify `plist` with the list of the properties `s` has (pl-file.c)."
function unify_stream_property_list(
    ld::PL_local_data{T}, s::IOSTREAM, plist::term_t
)::Bool where {T}
    tail = PL_copy_term_ref(ld, plist)
    head = PL_new_term_ref(ld)
    prop = PL_new_term_ref(ld)
    rc = true

    for p in sprop_list
        rc = _put_functor(ld, prop, p.name, p.arity)
        rc || break

        a1 = PL_new_term_ref(ld)
        p.arity == 0 || _PL_get_arg(ld, 1, prop, a1)
        rc = _call_stream_property(ld, s, p, a1)
        if rc
            rc = PL_unify_list(ld, tail, head, tail) && PL_unify(ld, head, prop)
            rc || break
        else
            PL_exception(ld, 0) != 0 && break
            rc = true
        end
    end

    rc = rc && PL_unify_nil(ld, tail)
    PL_reset_term_refs(ld, tail)

    return rc
end

# PORT: pl-file.c dstream_properties as pl_dstream_properties2_va
# (PRED_IMPL("\$stream_properties", 2, dstream_properties, 0)) — pl-file.c:5344-5356
# DIVERGES: no `PL_LOCK(L_FILE)`.
"`'\$stream_properties'(+Stream, -PropertyList)` (pl-file.c)."
function pl_dstream_properties2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    s = term_stream_handle(ld, A1, SH_ERRORS | SH_UNLOCKED)
    s === nothing && return FFALSE
    return unify_stream_property_list(ld, s, A2) ? FTRUE : FFALSE
end

# PORT: pl-file.c unify_stream_property
"Put the property `p` of `s` into the term reference `t` (pl-file.c)."
function unify_stream_property(
    ld::PL_local_data, s::IOSTREAM, p::sprop, t::term_t
)::Bool
    _put_functor(ld, t, p.name, p.arity) || return false
    a1 = PL_new_term_ref(ld)
    p.arity == 0 || _PL_get_arg(ld, 1, t, a1)
    rc = _call_stream_property(ld, s, p, a1)
    PL_reset_term_refs(ld, a1)
    return rc
end

# PORT: pl-file.c dstreams_properties as pl_dstreams_properties2_va
# (PRED_IMPL("\$streams_properties", 2, dstreams_properties, 0)) — pl-file.c:5387-5455
# DIVERGES: `newTableEnumPP(streamContext)` is the live entries of `PL_global_data.stream_table`, in the order the
# streams got their context (upstream: hash-table order); the table is copied first, the enumeration then sees no
# stream made or freed meanwhile; no `PL_LOCK(L_FILE)`; `can_unify` is `can_unify_cells` on the argument locations.
"`'\$streams_properties'(?Property, -Pairs)`: `Stream-Property` of each stream having it, or `Stream-PropertyList` for an unbound Property (pl-file.c)."
function pl_dstreams_properties2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    rc = false
    tail = PL_copy_term_ref(ld, A2)
    head = PL_new_term_ref(ld)
    streams = IOSTREAM[s for s in _query_gd(ld).stream_table if s !== nothing]

    p = get_stream_property_def(ld, A1)
    if p !== nothing
        st = PL_new_term_ref(ld)
        pt = PL_new_term_ref(ld)
        ex = PL_new_term_ref(ld)

        for s in streams
            Sacquire(s)
            rc =
                s.magic == SIO_MAGIC && s.context != 0 &&
                unify_stream_property(ld, s, p, pt)
            Srelease(s) && (rc = false)
            rc = (
                rc &&
                can_unify_cells(ld, -(A1 + 1), -(pt + 1), ex) &&
                PL_unify_list(ld, tail, head, tail) &&
                PL_unify_functor(ld, head, mk_sym(T, :-), 2) &&
                _PL_get_arg(ld, 1, head, st) &&
                unify_stream_ref(ld, st, s) &&
                PL_unify_arg(ld, 2, head, pt)
            )
            if !rc && (!PL_is_variable(ld, ex) || PL_exception(ld, 0) != 0)
                break
            end
        end
        if !PL_is_variable(ld, ex)
            rc = PL_raise_exception(ld, ex)
        else
            rc = PL_exception(ld, 0) == 0 && PL_unify_nil(ld, tail)
        end
    elseif PL_is_variable(ld, A1)
        st = PL_new_term_ref(ld)
        pl = PL_new_term_ref(ld)

        rc = true
        for s in streams
            rc = (
                s.context != 0 &&
                PL_unify_list(ld, tail, head, tail) &&
                PL_unify_functor(ld, head, mk_sym(T, :-), 2) &&
                _PL_get_arg(ld, 1, head, st) &&
                unify_stream_ref(ld, st, s) &&
                _PL_get_arg(ld, 2, head, pl) &&
                unify_stream_property_list(ld, s, pl)
            )
            rc || break
        end
        rc = PL_exception(ld, 0) == 0 && PL_unify_nil(ld, tail)
    end

    return rc ? FTRUE : FFALSE
end

# ── set_stream/2 (pl-file.c STREAM ATTRIBUTES) ───────────────────────────────────────────────────

# ORIGINAL: pl-error.c `PL_permission_error(operation, type, culprit)`, which the Julia error module has not.
"Raise `permission_error(Operation, Type, Culprit)`; false (pl-error.c `PL_permission_error`)."
function _PL_permission_error(
    ld::PL_local_data{T}, operation::Symbol, type::Symbol, culprit::term_t
)::Bool where {T}
    return PL_error(
        ld, "", 0, "", ERR_PERMISSION, mk_sym(T, operation), mk_sym(T, type), culprit
    )
end

# ORIGINAL: pl-prologflag.c `atom_to_unicode_atoms_ex`'s `domain_error(unicode_atoms, V)` checks, for the
# modes `set_stream/2` sets. `nfc` needs the unicode normalisation hook (`ensure_unicode_normalize_hook`, F1's
# flags) and is REFUSED (`NotPortedError`), as `open/4`'s `unicode_atoms` option is.
"The `Sunicode_atoms_t` the atom `val` names, else `nothing` after raising `domain_error(unicode_atoms, V)`."
function _atom_to_unicode_atoms(
    ld::PL_local_data{T}, val::T
)::Union{Nothing, Sunicode_atoms_t} where {T}
    _sym_is(val, :accept) && return S_UATOMS_ACCEPT
    _sym_is(val, :error) && return S_UATOMS_ERROR
    _sym_is(val, :reject) && return S_UATOMS_REJECT
    _sym_is(val, :nfc) && throw(
        NotPortedError{T}(val, "set_stream/2's unicode_atoms(nfc)", "F1 (the flags)")
    )
    v = PL_new_term_ref(ld)
    PL_put_atom(ld, v, val)
    PL_error(ld, "", 0, "", ERR_DOMAIN, mk_sym(T, :unicode_atoms), v)
    return nothing
end

# PORT: pl-file.c set_stream
# DIVERGES: not ported, each by the upstream line, with the answer the stream layer can give:
#  - `alias(Std)` of a standard stream name (file:2215-2227): `setStandardStream`, then `LD->prompt.next = true` for
#    `user_input` (`ld.prompt_next`, R2 LB5b). Its readers since R2 TOP1: `PL_write_prompt` (:1884, above; it clears the flag),
#    `PL_prompt_next` (pl-fli.c:5349, src/pl-fli.jl), `resetProlog` (pl-pro.c:67, src/pl-pro.jl) and, since R2 TOP1b A-D,
#    `PL_prompt_string` and `PL_prompt_is_continuation` (pl-fli.c:5364-5398, src/pl-fli.jl). The readers `Sread_user`
#    (pl-file.c:5992-6004), `wrapIO` (:6150), `set_prolog_IO/3` and pl-os.c `Sread_terminal` are left to TOP1b pieces E-G (status board row TOP1b:
#    the stream layer dispatches on the closed enum IOFUNCTIONS and `S_read` takes no local data; they wait for the audit's ruling on
#    where the stream handle's local data lives), so no read calls `PL_write_prompt` until then. Removal condition of this DIVERGES:
#    TOP1b ports those readers;
#  - `timeout(T)` (file:2325-2342, `Sset_timeout`): the stream layer has no timeout; `infinite` is what every stream
#    has and succeeds, any other time raises upstream's own failure, `permission_error(timeout, stream, S)`;
#  - `locale(L)` (file:2395-2404, `getLocaleEx`, `Ssetlocale`): REFUSED (`NotPortedError`), as open/4's `locale`;
#  - `close_on_exec(B)` (file:2455-2458, `setCloseOnExec`): the stream has no descriptor (`Sfileno(s) < 0`), upstream's
#    own `permission_error(close_on_exec, stream, S)` of that case;
#  - `unicode_atoms(nfc)` is refused (the normalisation hook, F1's flags); `buffer_size(N)` on an input stream
#    that holds more than N buffered bytes stops in `S__setbuf`'s `@assert` (upstream seeks back).
# `LD->encoding` is UTF-8 (the flag table is F1's); `file_name` accepts an atom or a string (`CVT_ATOM|CVT_STRING`).
"Set the attribute `aname` of the stream `s` to the term `a`; `stream` is the user's term (pl-file.c)."
function set_stream(
    ld::PL_local_data{T}, s::IOSTREAM, stream::term_t, aname::Symbol, a::term_t
)::Bool where {T}
    gd = _query_gd(ld)
    if aname === :alias                             # alias(name)
        alias = PL_get_atom_ex(ld, a)
        alias === nothing && return false

        i = standardStreamIndexFromName(ld, alias)
        if i >= 0
            setStandardStream(ld, i, s)
            i == 0 && (ld.prompt_next = true)       # changed Sinput: prompt! (pl-file.c:2224-2225)
            return true
        end

        aliasStream(gd, s, alias)
        return true
    elseif aname === :buffer                        # buffer(Buffering)
        b = PL_get_atom_ex(ld, a)
        b === nothing && return false
        return set_buffering(ld, s, b)
    elseif aname === :buffer_size
        size = PL_get_integer_ex(ld, a)
        size === nothing && return false
        size < 1 && return PL_error(ld, ERR_DOMAIN, mk_sym(T, :not_less_than_one), a)
        Ssetbuffer(s, nothing, size)
        return true
    elseif aname === :eof_action                    # eof_action(Action)
        action = PL_get_atom_ex(ld, a)
        action === nothing && return false
        return set_eof_action(ld, s, action)
    elseif aname === :type                          # type(Type)
        type = PL_get_atom_ex(ld, a)
        type === nothing && return false
        if _sym_is(type, :text)
            if (s.flags & SIO_TEXT) == 0 && Ssetenc(s, ENC_UTF8) != 0       # LD->encoding
                return _PL_permission_error(ld, :encoding, :stream, stream)
            end
            s.flags |= SIO_TEXT
        elseif _sym_is(type, :binary)
            if (s.flags & SIO_TEXT) != 0 && Ssetenc(s, ENC_OCTET) != 0
                return _PL_permission_error(ld, :encoding, :stream, stream)
            end
            s.flags &= ~SIO_TEXT
        else
            return PL_error(ld, "set_stream", 2, "", ERR_DOMAIN, mk_sym(T, :type), a)
        end
        return true
    elseif aname === :close_on_abort                # close_on_abort(Bool)
        close = PL_get_stdbool_ex(ld, a)
        close === nothing && return false
        if close
            s.flags &= ~SIO_NOCLOSE
        else
            s.flags |= SIO_NOCLOSE
        end
        return true
    elseif aname === :record_position
        rec = PL_get_stdbool_ex(ld, a)
        rec === nothing && return false
        if rec
            pb = s.posbuf                           # memset(&s->posbuf, 0, …); lineno = 1
            pb.byteno, pb.charno, pb.lineno, pb.linepos, pb.esc_state = 0, 0, 1, 0, 0
            s.position = pb
        else
            s.position = nothing
        end
        return true
    elseif aname === :line_position
        lpos = PL_get_integer_ex(ld, a)
        lpos === nothing && return false
        pos = s.position
        if pos !== nothing
            pos.linepos = lpos
            Sresetesc(pos)
        else
            return _PL_permission_error(ld, :line_position, :stream, stream)
        end
        return true
    elseif aname === :file_name                     # file_name(Atom)
        txt = PL_get_text(ld, a, CVT_ATOM | CVT_STRING | CVT_EXCEPTION)
        txt === nothing && return false
        setFileNameStream(gd, s, mk_sym(T, Symbol(text_string(txt))))
        return true
    elseif aname === :timeout
        v = PL_get_atom(ld, a)
        v !== nothing && _sym_is(v, :infinite) && return true       # Sset_timeout(s, -1) == 0
        PL_get_float_ex(ld, a) === nothing && return false
        return _PL_permission_error(ld, :timeout, :stream, stream)  # Sset_timeout(s, tmo) != 0
    elseif aname === :tty                           # tty(bool)
        val = PL_get_stdbool_ex(ld, a)
        val === nothing && return false
        if val
            s.flags |= SIO_ISATTY
        else
            s.flags &= ~SIO_ISATTY
        end
        return true
    elseif aname === :encoding                      # encoding(atom)
        val = PL_get_atom_ex(ld, a)
        val === nothing && return false
        if _sym_is(val, :bom)
            s2 = getStream(s)
            if s2 !== nothing
                if ScheckBOM(s2) == 0
                    return (s2.flags & SIO_BOM) != 0
                end
                return streamStatus(ld, s2)
            end
            return streamStatus(ld, s)
        end
        enc = PL_atom_to_encoding(val)
        if enc == ENC_UNKNOWN
            bad_encoding(ld, "", val)
            return false
        end

        Ssetenc(s, enc) == 0 && return true

        return _PL_permission_error(ld, :encoding, :stream, stream)
    elseif aname === :unicode_atoms
        val = PL_get_atom_ex(ld, a)
        val === nothing && return false
        mode = _atom_to_unicode_atoms(ld, val)
        mode === nothing && return false
        s.unicode_atoms = mode
        return true
    elseif aname === :locale                        # locale(Locale)
        throw(
            NotPortedError{T}(
                mk_sym(T, :locale), "set_stream/2's locale(Locale)", "PL_locale"
            )
        )
    elseif aname === :representation_errors
        val = PL_get_atom_ex(ld, a)
        val === nothing && return false

        s.flags &= ~(SIO_REPXML | SIO_REPPL | SIO_REPPLU)

        if _sym_is(val, :error)
        elseif _sym_is(val, :xml)
            s.flags |= SIO_REPXML
        elseif _sym_is(val, :prolog)
            s.flags |= SIO_REPPL
        elseif _sym_is(val, :unicode)
            s.flags |= SIO_REPPLU
        else
            return PL_error(ld, ERR_DOMAIN, mk_sym(T, :representation_errors), a)
        end
        return true
    elseif aname === :write_errors
        val = PL_get_atom_ex(ld, a)
        val === nothing && return false

        if _sym_is(val, :error)
            s.flags &= ~SIO_NOERROR
        elseif _sym_is(val, :ignore)
            s.flags |= SIO_NOERROR
        else
            return PL_domain_error(ld, "write_errors", a)
        end
        return true
    elseif aname === :newline
        val = PL_get_atom_ex(ld, a)
        val === nothing && return false

        mode = atom_to_newline_mode(ld, val, s.flags)
        mode === nothing && return false
        s.newline = mode & 0x3
        return true
    elseif aname === :close_on_exec                 # close_on_exec(bool)
        val = PL_get_stdbool_ex(ld, a)
        val === nothing && return false

        return _PL_permission_error(ld, :close_on_exec, :stream, stream)    # Sfileno(s) < 0
    end
    return false                                    # assert(0)
end

# PORT: pl-file.c SS_READ
"`set_stream/2` attribute applies to the input side of a stream (pl-file.c)."
const SS_READ = 0x01
# PORT: pl-file.c SS_WRITE
"`set_stream/2` attribute applies to the output side of a stream (pl-file.c)."
const SS_WRITE = 0x02
# PORT: pl-file.c SS_BOTH
"`set_stream/2` attribute applies to both sides of a stream (pl-file.c)."
const SS_BOTH = SS_READ | SS_WRITE
# PORT: pl-file.c SS_NOPAIR
"`set_stream/2` attribute is not allowed on a stream pair (pl-file.c)."
const SS_NOPAIR = 0x04
# PORT: pl-file.c SS_EITHER
"`set_stream/2` attribute applies to either side of a stream (pl-file.c)."
const SS_EITHER = SS_BOTH | SS_NOPAIR
# PORT: pl-file.c SS_NOLOCK
"`set_stream/2` attribute is set without locking the stream (pl-file.c)."
const SS_NOLOCK = 0x08

# PORT: pl-file.c ss_info
# DIVERGES: a tuple of (attribute name, flags), where upstream ends a C array with a zero atom.
"The attributes `set_stream/2` knows, with their `SS_*` flags (pl-file.c)."
const ss_info = (
    (:alias, SS_EITHER | SS_NOLOCK),
    (:buffer, SS_BOTH),
    (:buffer_size, SS_BOTH),
    (:eof_action, SS_READ),
    (:type, SS_BOTH),
    (:close_on_abort, SS_BOTH),
    (:record_position, SS_BOTH),
    (:line_position, SS_EITHER),
    (:file_name, SS_BOTH),
    (:timeout, SS_BOTH),
    (:tty, SS_BOTH),
    (:encoding, SS_BOTH),
    (:unicode_atoms, SS_READ),
    (:locale, SS_BOTH),
    (:representation_errors, SS_WRITE),
    (:write_errors, SS_WRITE),
    (:newline, SS_BOTH),
    (:close_on_exec, SS_BOTH)
)

# PORT: pl-file.c prop_get_stream
# DIVERGES: `s` is the stream of the table's entry `serial` (`nothing`: closed); no lock, so `lock` only picks
# `getStream` (the open stream) over the bare magic test, which are the same here.
"The stream `s` if it is open, else `nothing` after raising `existence_error(stream, Blob)` (pl-file.c)."
function prop_get_stream(
    ld::PL_local_data{T}, blob::T, s::Union{Nothing, IOSTREAM}, lock::Bool
)::Union{Nothing, IOSTREAM} where {T}
    if s !== nothing && s.magic == SIO_MAGIC
        return s
    end
    symbol_no_stream(ld, blob)
    return nothing
end

# PORT: pl-file.c set_stream as pl_set_stream2_va
# (PRED_IMPL("set_stream", 2, set_stream, 0)) — pl-file.c:2520-2594
# DIVERGES: `PL_get_stream_handle` is `term_stream_handle(SH_ERRORS|SH_ALIAS)` (reached for no blob: a pair is split
# above, by the attribute's `SS_NOPAIR`, so `SH_NOPAIR` is moot); no lock to release.
"`set_stream(+Stream, +Attribute)`: set the attribute of the stream (pl-file.c)."
function pl_set_stream2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    aval = PL_new_term_ref(ld)

    stream = A1
    attr = A2

    na = PL_get_name_arity(ld, attr)
    local flags::Int
    local aname::Symbol
    if na !== nothing && na[2] == 1
        nm = na[1]
        (kind(nm) === SYM && !is_reserved_symbol(nm) && !is_blob(nm)) ||
            return PL_domain_error(ld, "stream_attribute", attr) ? FTRUE : FFALSE
        name = Symbol(sym_text(nm))
        i = findfirst(info -> info[1] === name, ss_info)
        i === nothing &&
            return PL_domain_error(ld, "stream_attribute", attr) ? FTRUE : FFALSE
        aname, flags = ss_info[i]
    else
        return PL_type_error(ld, "stream_attribute", attr) ? FTRUE : FFALSE
    end

    _PL_get_arg(ld, 1, attr, aval)

    sblob = PL_get_atom(ld, stream)
    sblob === nothing && return not_a_stream(ld, stream, SH_ALIAS) ? FTRUE : FFALSE

    gd = _query_gd(ld)
    ref = _stream_ref_of(ld, sblob)
    if ref !== nothing                              # got a stream handle
        if ref.read != 0 && ref.write != 0 && (flags & SS_NOPAIR) != 0    # stream pair
            return symbol_stream_pair_not_allowed(ld, sblob) ? FTRUE : FFALSE
        end

        rc = true
        lock = (flags & SS_NOLOCK) == 0
        if ref.read != 0 && (flags & SS_READ) != 0
            s = prop_get_stream(ld, sblob, _stream_of(gd, ref.read), lock)
            s === nothing && return FFALSE
            rc = set_stream(ld, s, stream, aname, aval)
        end
        if rc && ref.write != 0 && (flags & SS_WRITE) != 0
            s = prop_get_stream(ld, sblob, _stream_of(gd, ref.write), lock)
            s === nothing && return FFALSE
            rc = set_stream(ld, s, stream, aname, aval)
        end
    else
        s = term_stream_handle(ld, stream, SH_ERRORS | SH_ALIAS)    # PL_get_stream_handle
        rc = s !== nothing && set_stream(ld, s, stream, aname, aval)
    end

    return rc ? FTRUE : FFALSE
end

# PORT: pl-file.c symbol_stream_pair_not_allowed
"Raise `type_error(stream, Symbol)`, 'operation is ambiguous on a stream pair' (pl-file.c); false."
function symbol_stream_pair_not_allowed(ld::PL_local_data{T}, symbol::T)::Bool where {T}
    t = PL_new_term_ref(ld)
    setSlotValue!(ld, t + 1, symbol)                        # PL_put_atom(t, symbol)
    return PL_error(
        ld, "", 0, "operation is ambiguous on a stream pair", ERR_TYPE, mk_sym(T, :stream),
        t
    )
end

# PORT: pl-file.c set_prolog_IO as pl_set_prolog_IO3_va
# (PRED_IMPL("set_prolog_IO", 3, set_prolog_IO, 0)) — pl-file.c:6125-6167
# DIVERGES: no `PL_LOCK(L_FILE)`/`releaseStream` (no threads, no stream locks); `LD->IO.streams[0]` is `Suser_input`;
# the wrap is `wrapIO(gd, ld, in, true)` (`Sread_user`, see there).
"`set_prolog_IO(+In, +Out, +Error)`: make the three streams the user streams, `In` read with a prompt (pl-file.c)."
function pl_set_prolog_IO3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    io = getIOStreams(ld, PL__t0, PL__t0 + 1, PL__t0 + 2)
    io === nothing && return FFALSE
    in, out, error = io

    wrapin = Suser_input(ld) !== in

    setStandardStream(ld, SNO_USER_OUTPUT, out)
    setStandardStream(ld, SNO_USER_ERROR, error)
    setStandardStream(ld, SNO_CURRENT_OUTPUT, out)

    if wrapin
        setStandardStream(ld, SNO_CURRENT_INPUT, in)
        setStandardStream(ld, SNO_USER_INPUT, in)
        wrapIO(_query_gd(ld), ld, in, true)
        ld.prompt_next = true
    end

    posbuf = (Suser_input(ld)::IOSTREAM).posbuf
    for i in SNO_USER_INPUT:SNO_USER_ERROR
        st = ld.IO_streams[i + 1]::IOSTREAM
        st.position = posbuf
        st.flags |= SIO_RECORDPOS
    end

    return FTRUE
end

# `pl_set_prolog_IO3_va` stands before the table (a `const` tuple names it); `getIOStreams` and `wrapIO` are looked up at the call.

# PORT: pl-file.c BeginPredDefs as PL_predicates_from_file
# DIVERGES: the entries of the predicates the kernel has ported (LB5: current_input/1, current_output/1, line_count/2,
# line_position/2, tab/1,2, at_end_of_stream/0,1, get_code/1,2, put_code/1,2 and its alias put_char/1,2; S1: open/3,4 and close/1,2; S2a: prompt/2, prompt1/1, get_char/2, peek_char/2, flush_output/1, skip/2, ttyflush/0, is_stream/1, get_single_char/1, '\$alias_stream'/2, the input context trio and '\$stream_property'/2, '\$stream_properties'/2, '\$streams_properties'/2 and set_stream/2; lane D (UNTESTED): set_input/1, set_output/1, get_char/1, get_byte/1,2, peek_char/1, peek_code/1,2, peek_byte/1,2, put_byte/1,2, flush_output/0, put/1,2, skip/1, get/1,2, get0/1,2 (upstream's alias of get_code), byte_count/2, character_count/2, see/1, seen/0, seeing/1, tell/1, append/1, telling/1, told/0, open_null_stream/1, stream_pair/3, set_stream_position/2, seek/4, set_end_of_stream/1; LB2:
# source_location/2 and '$set_source_location'/2, upstream's order file:6396-6397); `PRED_DEF` ors in `PL_FA_VARARGS`.
"pl-file.c's registration table (`BeginPredDefs(file)`): the ported entries."
const PL_predicates_from_file = (
    PL_extension("open", 4, pl_open4_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("open", 3, pl_open3_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("close", 1, pl_close1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("close", 2, pl_close2_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("open_null_stream", 1, pl_open_null_stream1_va, PL_FA_VARARGS),
    PL_extension("stream_pair", 3, pl_stream_pair3_va, PL_FA_VARARGS),
    PL_extension("set_stream_position", 2, pl_set_stream_position2_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("seek", 4, pl_seek4_va, PL_FA_VARARGS),
    PL_extension("set_end_of_stream", 1, pl_set_end_of_stream1_va, PL_FA_VARARGS),
    PL_extension("fill_buffer", 1, pl_fill_buffer1_va, PL_FA_VARARGS),
    PL_extension("read_pending_codes", 3, pl_read_pending_codes3_va, PL_FA_VARARGS),
    PL_extension("read_pending_chars", 3, pl_read_pending_chars3_va, PL_FA_VARARGS),
    PL_extension("peek_string", 3, pl_peek_string3_va, PL_FA_VARARGS),
    PL_extension("copy_stream_data", 3, pl_copy_stream_data3_va, PL_FA_VARARGS),
    PL_extension("copy_stream_data", 2, pl_copy_stream_data2_va, PL_FA_VARARGS),
    PL_extension("\$size_stream", 2, pl_dsize_stream2_va, PL_FA_VARARGS),
    PL_extension("see", 1, pl_see1_va, PL_FA_VARARGS),
    PL_extension("seen", 0, pl_seen0_va, PL_FA_VARARGS),
    PL_extension("seeing", 1, pl_seeing1_va, PL_FA_VARARGS),
    PL_extension("tell", 1, pl_tell1_va, PL_FA_VARARGS),
    PL_extension("append", 1, pl_append1_va, PL_FA_VARARGS),
    PL_extension("telling", 1, pl_telling1_va, PL_FA_VARARGS),
    PL_extension("told", 0, pl_told0_va, PL_FA_VARARGS),
    PL_extension("set_input", 1, pl_set_input1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("set_output", 1, pl_set_output1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("get_char", 2, pl_get_char2_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("get_char", 1, pl_get_char1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("get_byte", 2, pl_get_byte2_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("get_byte", 1, pl_get_byte1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("peek_char", 2, pl_peek_char2_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("peek_char", 1, pl_peek_char1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("peek_code", 2, pl_peek_code2_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("peek_code", 1, pl_peek_code1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("peek_byte", 2, pl_peek_byte2_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("peek_byte", 1, pl_peek_byte1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("put_byte", 2, pl_put_byte2_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("put_byte", 1, pl_put_byte1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("flush_output", 0, pl_flush_output0_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("flush_output", 1, pl_flush_output1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("put", 2, pl_put2_va, PL_FA_VARARGS),
    PL_extension("put", 1, pl_put1_va, PL_FA_VARARGS),
    PL_extension("skip", 1, pl_skip1_va, PL_FA_VARARGS),
    PL_extension("get", 1, pl_get1_va, PL_FA_VARARGS),
    PL_extension("get", 2, pl_get2_va, PL_FA_VARARGS),
    PL_extension("get0", 2, pl_get_code2_va, PL_FA_VARARGS),
    PL_extension("get0", 1, pl_get_code1_va, PL_FA_VARARGS),
    PL_extension("byte_count", 2, pl_byte_count2_va, PL_FA_VARARGS),
    PL_extension("character_count", 2, pl_character_count2_va, PL_FA_VARARGS),
    PL_extension("current_input", 1, pl_current_input1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("current_output", 1, pl_current_output1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("line_count", 2, pl_line_count2_va, PL_FA_VARARGS),
    PL_extension("line_position", 2, pl_line_position2_va, PL_FA_VARARGS),
    PL_extension("tab", 2, pl_tab2_va, PL_FA_VARARGS),
    PL_extension("tab", 1, pl_tab1_va, PL_FA_VARARGS),
    PL_extension("at_end_of_stream", 1, pl_at_end_of_stream1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("at_end_of_stream", 0, pl_at_end_of_stream0_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("get_code", 2, pl_get_code2_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("get_code", 1, pl_get_code1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("put_code", 2, pl_put_code2_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("put_code", 1, pl_put_code1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("put_char", 2, pl_put_code2_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("put_char", 1, pl_put_code1_va, PL_FA_ISO | PL_FA_VARARGS),
    PL_extension("skip", 2, pl_skip2_va, PL_FA_VARARGS),
    PL_extension("ttyflush", 0, pl_ttyflush0_va, PL_FA_VARARGS),
    PL_extension("prompt", 2, pl_prompt2_va, PL_FA_VARARGS),
    PL_extension("is_stream", 1, pl_is_stream1_va, PL_FA_VARARGS),
    PL_extension("prompt1", 1, pl_prompt1_1_va, PL_FA_VARARGS),
    PL_extension("get_single_char", 1, pl_get_single_char1_va, PL_FA_VARARGS),
    PL_extension("source_location", 2, pl_source_location2_va, PL_FA_VARARGS),
    PL_extension("\$set_source_location", 2, pl_set_source_location2_va, PL_FA_VARARGS),
    PL_extension("\$stream_property", 2, pl_dstream_property2_va, PL_FA_VARARGS),
    PL_extension("\$stream_properties", 2, pl_dstream_properties2_va, PL_FA_VARARGS),
    PL_extension("\$streams_properties", 2, pl_dstreams_properties2_va, PL_FA_VARARGS),
    PL_extension("\$alias_stream", 2, pl_dalias_stream2_va, PL_FA_VARARGS),
    PL_extension("set_stream", 2, pl_set_stream2_va, PL_FA_VARARGS),
    PL_extension("set_prolog_IO", 3, pl_set_prolog_IO3_va, PL_FA_VARARGS),
    PL_extension("\$push_input_context", 1, pl_push_input_context1_va, PL_FA_VARARGS),
    PL_extension("\$pop_input_context", 0, pl_pop_input_context0_va, PL_FA_VARARGS),
    PL_extension("\$input_context", 1, pl_input_context1_va, PL_FA_VARARGS)
)

#
# THE OUTPUT REDIRECT of pl-file.c (R2's O1B): the output context stack (`pushOutputContext`,
# `popOutputContext`), the `redir_context` of pl-incl.h and its three functions
# (`setupOutputRedirect`, `closeOutputRedirect`, `discardOutputRedirect`) that `format/3` and
# `with_output_to/2` share, `with_output_to/2` itself, and `tellString`/`toldString`, the redirect of
# the current output to a memory stream that `format/2`'s column handling (`pending`, pl-fmt.c) and
# `~@` use. The sinks are the target of `with_output_to/2` and `format/3`: a stream (or alias, `user`,
# the current output) or one of `atom(A)`, `string(S)`, `codes(C)`, `codes(C, T)`, `chars(C)`,
# `chars(C, T)`.
#
# NOT PORTED: the locks of the stream layer (`Sacquire` counts only), `Sdprintf`'s message when a
# redirected current output was closed meanwhile.

# PORT: pl-file.c setStandardStream
"Make `s` standard stream number `i` of `ld`, taking a reference to it and releasing the old one (pl-file.c)."
function setStandardStream(ld::PL_local_data, i::Int, s::Union{Nothing, IOSTREAM})::Nothing
    old = ld.IO_streams[i + 1]
    if old !== s
        s !== nothing && Sacquire(s)
        ld.IO_streams[i + 1] = s
        old !== nothing && Srelease(old)
    end
    return nothing
end

# ── INTERACTION: wrapping the stream `set_prolog_IO/3` reads from (R2 TOP1b E) ───────────────────────────────────
# `wrapIO` replaces the read of a stream by `Sread_user`, which prompts as `Sread_terminal` does but without the tty
# test (pl-file.c:5959-6045). The record is `IOSTREAM.wrapped` (src/os/pl-stream.jl `wrappedIO`); `S_read` and
# `S_close` look at it first. DIVERGES (owner TH1): upstream's `GET_LD` in `Sread_user` is the thread's `LD`; the stream
# holds the number of its engine in `gd.ld_table` (`registerLocalData!`) and `S_read` looks it up there, the engine's term
# type being known only from the entry (`Sread_user`'s method on `PL_local_data{T}`).

# PORT: pl-file.c WRAP_CLEAR_FLAGS
# (swipl-devel cbf4e189, src/os/pl-file.c:5967)
"The flags `wrapIO` clears on the stream it wraps and `closeWrappedIO` restores (pl-file.c)."
const WRAP_CLEAR_FLAGS = SIO_FILE

# ORIGINAL (audit D-0462): an inference barrier at `S_read`'s one call of `Sread_user`, whose argument is the registry
# entry (`Union{Nothing, AbstractLocalData}`). Upstream's callee is a function pointer unknown at compile time
# (`(*wio->wrapped_functions->read)(...)`, swipl-devel 18168e62 src/os/pl-file.c:6039); here the abstract call matches
# TWO methods (the one on `PL_local_data{T}` and the fallback on the union), more than `@max_methods 1` allows, so
# inference gives up on the call and does not infer `Sread_user`'s body with the term type free. The call stays the one
# runtime dispatch it was (`JET_DISPATCH_ALLOWED`); the body is analysed per term type by its own manifest entries.
Base.Experimental.@max_methods 1 function Sread_user end

# PORT: pl-file.c Sread_user
# (swipl-devel cbf4e189, src/os/pl-file.c:5987-6007)
# DIVERGES: `handle` is the record `wio` and `buf` is `mem` from `from`, `Sttymode(wio->wrapped_stream)` has the stream
# `s` (what `S_read` was called on); `wrapped_functions->read` is `S_read_wrapped` (the stream's own function set, or the
# record's next wrapper's: a stream is wrapped once, see `wrapIO`); `Suser_output`/`Suser_input` are the engine's.
"Read for a wrapped stream: prompt as the toplevel does, read, map ^D to end-of-file, re-arm the prompt after a line (pl-file.c)."
function Sread_user(
    ld::PL_local_data{T}, s::IOSTREAM, wio::wrappedIO, mem::Vector{UInt8}, from::Int,
    size::Int
)::Int where {T}
    gd = ld.GD::PL_global_data{T}                       # (`wrapIO` records it)
    if ld.prompt_next && Sttymode(s) != TTY_RAW
        PL_write_prompt(gd, ld, true)
    else
        uo = Suser_output(ld)
        uo === nothing || Sflush(uo)
    end

    rc = S_read_wrapped(s, mem, from, size)
    if rc == 0                                          # end-of-file
        ui = Suser_input(ld)
        ui === nothing || Sclearerr(ui)
        ld.prompt_next = true
    elseif rc == 1 && mem[from] == 0x04
        rc = 0                                          # Map ^D to end-of-file
    elseif rc > 0 && mem[from + rc - 1] == UInt8('\n')
        ld.prompt_next = true
    end

    return rc
end

# (the local data was freed meanwhile: no engine to prompt for, a read error). The argument is the union, not `Nothing`
# alone: a second method under the abstract call is the barrier above; a `PL_local_data{T}` takes the method above (more
# specific), so only `nothing` reaches this one at run time.
Sread_user(
    ::Union{Nothing, AbstractLocalData}, ::IOSTREAM, ::wrappedIO, ::Vector{UInt8}, ::Int,
    ::Int
)::Int = -1

# PORT: pl-file.c closeWrappedIO
# (swipl-devel cbf4e189, src/os/pl-file.c:6010-6027)
# DIVERGES: `handle`/`functions` were never replaced (see `wrappedIO`), so the restore is `wrapped = nothing` and the
# flags; the record's entry in `gd.ld_table` is freed; `PL_free(wio)` is Julia's GC.
"Close a wrapped stream: its own close, then the wrapper goes and the flags it cleared come back (pl-file.c)."
function closeWrappedIO(s::IOSTREAM, wio::wrappedIO)::Int
    rval = S_close_wrapped(s)

    s.wrapped = nothing
    s.flags &= ~WRAP_CLEAR_FLAGS
    s.flags |= wio.saved_flags
    unregisterLocalData!(wio.table, wio.ld)

    return rval
end

# NOT PORTED: controlWrappedIO (pl-file.c:6030-6044): the kernel's function sets have no `control` to pass to.

# PORT: pl-file.c wrapIO
# (swipl-devel cbf4e189, src/os/pl-file.c:6047-6068)
# DIVERGES: the database `gd` is an argument (the table the engine is registered in); `read` is whether the replacement is
# `Sread_user` (the only one given) and `write` is not a parameter (always NULL); a stream wrapped twice keeps its one
# record with the new engine registered (upstream chains two function blocks, and closing the outer frees the inner's:
# a use after free); the engine records its database in `ld.GD` if it has none (`PL_open_query` does it for a query).
"Wrap `s` for `ld`: clear `WRAP_CLEAR_FLAGS`, remember them, and read with `Sread_user` (pl-file.c)."
function wrapIO(
    gd::PL_global_data{T}, ld::PL_local_data{T}, s::IOSTREAM, read::Bool
)::Nothing where {T}
    ld.GD === nothing && (ld.GD = gd)
    old = s.wrapped
    if old !== nothing
        unregisterLocalData!(old.table, old.ld)
        old.table = gd.ld_table
        old.ld = registerLocalData!(gd.ld_table, ld)
        old.user_read |= read
        return nothing
    end

    saved = s.flags & WRAP_CLEAR_FLAGS
    s.flags &= ~WRAP_CLEAR_FLAGS
    s.wrapped = wrappedIO(gd.ld_table, registerLocalData!(gd.ld_table, ld), read, saved)
    return nothing
end

# PORT: pl-file.c Swrite_stderr
# (swipl-devel cbf4e189, src/os/pl-file.c:6071-6079)
# DIVERGES: `buf` is `mem` from `from`; `Sfwrite` is its loop over `Sputc` (pl-stream.c:1577-1587, the count of bytes written).
"Write to the stream `org` the error stream copies, and flush it (pl-file.c): the count, or -1."
function Swrite_stderr(org::IOSTREAM, mem::Vector{UInt8}, from::Int, size::Int)::Int
    rc = 0
    for i in from:(from + size - 1)
        Sputc(Int(mem[i]), org) < 0 && break
        rc += 1
    end

    return (rc > 0 && Sflush(org) == 0) ? rc : -1
end

# NOT PORTED as a table: `Sstderrfunctions` (pl-file.c:6081-6090) is the enum member of that name, `S_write` and `S_close`
# dispatch on it (no `read`, `seek`, `control`: a stream made over it is an output).

# PORT: pl-file.c getIOStreams
# (swipl-devel cbf4e189, src/os/pl-file.c:6093-6122)
# DIVERGES: the streams are the result (upstream: three out parameters and `bool`), `nothing` with the error raised;
# `PL_get_stream(t, &s, SIO_INPUT)` is `term_stream_handle(SH_ERRORS|SH_ALIAS|SH_INPUT)` (pl-file.c:973-986), no lock to
# release; `PL_compare` raises nothing here (no `CMP_ERROR`); `SIO_ABUF` is `SIO_FBUF|SIO_LBUF|SIO_NBUF`.
"The input, output and error streams `set_prolog_IO/3` names; a separate error stream if Out == Error (pl-file.c)."
function getIOStreams(
    ld::PL_local_data{T}, tin::term_t, tout::term_t, terror::term_t
)::Union{Nothing, Tuple{IOSTREAM, IOSTREAM, IOSTREAM}} where {T}
    in = term_stream_handle(ld, tin, SH_ERRORS | SH_ALIAS | SH_INPUT)
    in === nothing && return nothing

    out = term_stream_handle(ld, tout, SH_ERRORS | SH_ALIAS | SH_OUTPUT)
    out === nothing && return nothing

    local error::IOSTREAM
    if PL_compare(ld, tout, terror) == CMP_EQUAL         # ==
        err = getStream(Snew(out, out.flags & ~WRAP_CLEAR_FLAGS, Sstderrfunctions))
        err === nothing && return nothing
        error = err
    else
        e = term_stream_handle(ld, terror, SH_ERRORS | SH_ALIAS | SH_OUTPUT)
        e === nothing && return nothing
        error = e
    end

    out.flags &= ~(SIO_FBUF | SIO_LBUF | SIO_NBUF)       # output: line buffered
    out.flags |= SIO_LBUF

    error.flags &= ~(SIO_FBUF | SIO_LBUF | SIO_NBUF)     # disable buffering
    error.flags |= SIO_NBUF

    return (in, out, error)
end

# PORT: pl-file.c pushOutputContext
# DIVERGES: the context stack is a Vector of the streams (upstream: a linked list of
# `struct output_context`, `LD->IO.output_stack`).
"Make `s` the current output; the old current output waits on the output context stack (pl-file.c)."
function pushOutputContext(ld::PL_local_data, s::IOSTREAM)::Nothing
    cur = Scurout(ld)::IOSTREAM
    push!(ld.IO_output_stack, cur)                  # c->stream = Scurout
    Sacquire(cur)
    setStandardStream(ld, SNO_CURRENT_OUTPUT, s)
    return nothing
end

# PORT: pl-file.c popOutputContext
# DIVERGES: no `Sdprintf` message when the stream waiting on the stack was closed meanwhile; `Soutput`
# is the `user_output` of `ld`.
"Restore the current output the last `pushOutputContext` saved; without one it is `user_output` (pl-file.c)."
function popOutputContext(ld::PL_local_data)::Nothing
    if !isempty(ld.IO_output_stack)
        c = pop!(ld.IO_output_stack)
        s = c
        if s.magic != SIO_MAGIC                     # current_output closed; set to user_output
            s = Suser_output(ld)
        end
        setStandardStream(ld, SNO_CURRENT_OUTPUT, s)
        Srelease(c)
    else
        setStandardStream(ld, SNO_CURRENT_OUTPUT, Suser_output(ld))
    end
    return nothing
end

# PORT: pl-incl.h REDIR_MAGIC
"The magic of a live `redir_context` (pl-incl.h)."
const REDIR_MAGIC = 0x23a9bef3

# PORT: pl-incl.h redir_context
# DIVERGES: no `buffer[1024]`: the memory file grows from empty (as `atom_to_term`'s); `data` and `size`
# are references, the memory stream's buffer and its length in BYTES (upstream counts `wchar_t`s: the
# stream is UTF-8, see `setupOutputRedirect`).
"The state of a redirect of the output (pl-incl.h): its stream, its target and the memory it writes."
mutable struct redir_context
    magic::Int                                              # REDIR_MAGIC
    stream::Union{Nothing, IOSTREAM}                        # temporary output
    is_stream::Bool                                         # redirect to stream
    redirected::Bool                                        # output is redirected
    term::term_t                                            # redirect target
    out_format::Int                                         # output type (PL_ATOM, PL_STRING, PL_CODE_LIST, PL_CHAR_LIST)
    out_arity::Int                                          # 2 for difference-list versions
    size::Base.RefValue{Int}                                # size of the data written
    data::Base.RefValue{Union{Nothing, Vector{UInt8}}}      # data written
end
redir_context() = redir_context(
    0, nothing, false, false, 0, 0, 0, Ref(0),
    Ref{Union{Nothing, Vector{UInt8}}}(nothing)
)

# PORT: pl-file.c setupOutputRedirect
# DIVERGES: the memory stream is UTF-8 (upstream `ENC_WCHAR`, which this kernel's stream layer refuses:
# the R1 UTF-8 rule); `to` is 0 for the current output.
"""
    setupOutputRedirect(ld, to, ctx, redir) -> Bool

Prepare the redirect of the output to `to` (pl-file.c): 0 the current output, a stream, an alias or
`user`, or one of `atom(A)`, `string(S)`, `codes(C[, T])`, `chars(C[, T])`, for which a memory stream is
opened. With `redir` it is made the current output. False with the error raised.
"""
function setupOutputRedirect(
    ld::PL_local_data{T}, to::term_t, ctx::redir_context, redir::Bool
)::Bool where {T}
    ctx.term = to
    ctx.redirected = redir

    a = to == 0 ? nothing : PL_get_atom(ld, to)         # the alias or stream handle `to` holds
    if to == 0
        cur = Scurout(ld)
        s = cur === nothing ? nothing : getStream(cur)
        s === nothing && return no_stream(ld, to, :current_output)
        ctx.stream = s
        ctx.is_stream = true
    elseif a !== nothing
        if isTextAtom(a) && sym_key(a) == sym_key(mk_sym(T, :user))
            uo = Suser_output(ld)
            s = uo === nothing ? nothing : getStream(uo)
            s === nothing && return no_stream(ld, to, :user)
            ctx.stream = s
            ctx.is_stream = true
        else
            s = get_stream_handle(ld, a, SH_OUTPUT | SH_ERRORS)
            s === nothing && return false
            ctx.stream = s
            if (s.flags & SIO_OUTPUT) == 0
                return PL_error(
                    ld, "", 0, "", ERR_PERMISSION, mk_sym(T, :output), mk_sym(T, :stream),
                    to
                )
            end
            ctx.is_stream = true
        end
    else
        if PL_is_functor(ld, to, mk_sym(T, :codes), 2)
            ctx.out_format = PL_CODE_LIST
            ctx.out_arity = 2
        elseif PL_is_functor(ld, to, mk_sym(T, :codes), 1)
            ctx.out_format = PL_CODE_LIST
            ctx.out_arity = 1
        elseif PL_is_functor(ld, to, mk_sym(T, :chars), 2)
            ctx.out_format = PL_CHAR_LIST
            ctx.out_arity = 2
        elseif PL_is_functor(ld, to, mk_sym(T, :chars), 1)
            ctx.out_format = PL_CHAR_LIST
            ctx.out_arity = 1
        elseif PL_is_functor(ld, to, mk_sym(T, :string), 1)
            ctx.out_format = PL_STRING
            ctx.out_arity = 1
        elseif PL_is_functor(ld, to, mk_sym(T, :atom), 1)
            ctx.out_format = PL_ATOM
            ctx.out_arity = 1
        else
            return PL_error(ld, ERR_TYPE, mk_sym(T, :output), to)
        end

        ctx.is_stream = false
        ctx.data[] = nothing
        ctx.size[] = 0
        stream = Sopenmem(ctx.data, ctx.size, "w")
        stream === nothing && error("setupOutputRedirect: Sopenmem")
        stream.encoding = ENC_UTF8
        ctx.stream = stream
    end

    ctx.magic = REDIR_MAGIC

    redir && pushOutputContext(ld, ctx.stream::IOSTREAM)

    return true
end

# PORT: pl-file.c closeOutputRedirect
# DIVERGES: the text written is the UTF-8 bytes of the memory file, unified through `PL_unify_text`
# (upstream: `PL_unify_wchars_diff` on `wchar_t`s, the same text and list); `freeStream` runs after
# `Sclose` for a stream that Prolog got to know (`current_output(S)`), as it is run for upstream's close hook.
"""
    closeOutputRedirect(ld, ctx) -> Bool

End the redirect `ctx`, restoring the current output; a memory sink is unified with what was written
(pl-file.c). False when that fails.
"""
function closeOutputRedirect(ld::PL_local_data{T}, ctx::redir_context)::Bool where {T}
    rval = true
    ctx.magic != REDIR_MAGIC && return rval             # already done
    ctx.magic = 0

    ctx.redirected && popOutputContext(ld)

    s = ctx.stream::IOSTREAM
    if ctx.is_stream
        rval = streamStatus(ld, s)
    else
        out = PL_new_term_ref(ld)

        if Sclose(s) == 0
            s.context != 0 && freeStream(ld, s)
            _PL_get_arg(ld, 1, ctx.term, out)
            if ctx.out_arity == 2
                diff = PL_new_term_ref(ld)
                _PL_get_arg(ld, 2, ctx.term, diff)
                tail = PL_new_term_ref(ld)
            else
                diff = tail = 0
            end

            b = ctx.data[]
            bytes = (b === nothing || ctx.size[] == 0) ? UInt8[] : b[1:ctx.size[]]
            text = PL_chars_t(bytes, length(String(copy(bytes))), ENC_UTF8, false)
            rval = PL_unify_text(ld, out, tail, text, ctx.out_format)
            if rval && tail != 0
                rval = PL_unify(ld, tail, diff)
            end
        else
            s.context != 0 && freeStream(ld, s)
            rval = false
        end
    end

    return rval
end

# PORT: pl-file.c discardOutputRedirect
"""
    discardOutputRedirect(ld, ctx)

End the redirect `ctx` because its implementation failed or raised (pl-file.c): the current output is
restored, a memory stream closed and its text dropped. The stream error state of a stream sink is
checked, as an error there makes the continuation meaningless.
"""
function discardOutputRedirect(ld::PL_local_data, ctx::redir_context)::Nothing
    ctx.magic != REDIR_MAGIC && return nothing          # already done

    ctx.magic = 0

    ctx.redirected && popOutputContext(ld)

    s = ctx.stream::IOSTREAM
    if ctx.is_stream
        streamStatus(ld, s)
    else
        closeStream(ld, s)
        ctx.data[] = nothing
    end
    return nothing
end

# PORT: pl-file.c with_output_to as pl_with_output_to2_va
# (PRED_IMPL("with_output_to", 2, with_output_to, PL_FA_TRANSPARENT))
"""
`with_output_to(+Sink, :Goal)`: run `Goal` once, the current output redirected to `Sink`; when it
succeeds, `Sink` is unified with what it wrote; failure and exceptions discard the output (pl-file.c).
"""
function pl_with_output_to2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    outctx = redir_context()

    if setupOutputRedirect(ld, A1, outctx, true)
        ex = Ref(0)

        rval = callProlog(_query_gd(ld), ld, 0, A2, PL_Q_CATCH_EXCEPTION, ex)
        if rval
            return closeOutputRedirect(ld, outctx) ? FTRUE : FFALSE
        end
        discardOutputRedirect(ld, outctx)
        if ex[] != 0
            PL_raise_exception(ld, ex[])
            return FFALSE
        end
    end

    return FFALSE
end

# PORT: pl-file.c tellString
"""
    tellString(ld, bufp, sizep, enc) -> Bool

Redirect the current output to a memory stream in encoding `enc`; what it writes is in `bufp[]` and
`sizep[]` (bytes) once flushed. `toldString` ends it (pl-file.c).
"""
function tellString(
    ld::PL_local_data, bufp::Base.RefValue{Union{Nothing, Vector{UInt8}}},
    sizep::Base.RefValue{Int}, enc::IOENC
)::Bool
    stream = Sopenmem(bufp, sizep, "w")
    stream === nothing && error("tellString: Sopenmem")
    stream.encoding = enc
    pushOutputContext(ld, stream)

    return true
end

# PORT: pl-file.c toldString
"End the redirect `tellString` began: restore the current output and close the memory stream (pl-file.c)."
function toldString(ld::PL_local_data)::Bool
    cur = Scurout(ld)
    s = cur === nothing ? nothing : getStream(cur)
    s === nothing && return true

    if s.functions == Smemfunctions
        popOutputContext(ld)
        closeStream(ld, s)
    end

    return true
end

# PORT: pl-file.c BeginPredDefs as PL_predicates_from_redirect
# DIVERGES: a table of its own (the entry belongs to `BeginPredDefs(file)`, upstream's order
# file:6381), as the predicate needs `callProlog`, which loads after pl-file.jl.
"pl-file.c's registration table for the redirect: `with_output_to/2`."
const PL_predicates_from_redirect = (
    PL_extension(
        "with_output_to", 2, pl_with_output_to2_va, PL_FA_VARARGS | PL_FA_TRANSPARENT
    ),
)
