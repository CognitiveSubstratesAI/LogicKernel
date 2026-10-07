# UPSTREAM: swipl-devel src/os/pl-stream.c @ bae881a2
# UPSTREAM: swipl-devel src/os/SWI-Stream.h @ bae881a2
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2026, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
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
# the three function sets, and `handle` their record, where upstream holds function pointers and a
# `void *`. NOT PORTED: locks and threads, timeouts, `tee`, filter streams (`upstream`,
# `downstream`), locales, ENC_ANSI, ENC_UTF16* and ENC_WCHAR (refused where a stream would use
# them), the pending exception (`Sset_exception`), close hooks, `Sfprintf` and the other formatted
# output.

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
# PORT: SWI-Stream.h SIO_STATIC
"The stream is in static memory (SWI-Stream.h)."
const SIO_STATIC = UInt32(1) << 10
# PORT: SWI-Stream.h SIO_RECORDPOS
"Maintain the position (SWI-Stream.h)."
const SIO_RECORDPOS = UInt32(1) << 11
# PORT: SWI-Stream.h SIO_NOFEOF
"Do not set `SIO_FEOF` (SWI-Stream.h)."
const SIO_NOFEOF = UInt32(1) << 14
# PORT: SWI-Stream.h SIO_TEXT
"Text-mode operation (SWI-Stream.h)."
const SIO_TEXT = UInt32(1) << 15
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
# `S_write`, `S_seek64`, `S_close` and `S_control` dispatch on it.
"Which function set a stream reads, writes, seeks and closes with (SWI-Stream.h `IOFUNCTIONS`)."
@enum IOFUNCTIONS::UInt8 begin
    Smemfunctions
    Sstringfunctions
    Siofunctions
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

# ORIGINAL: the handle of `Siofunctions` — a Julia IO in place of the OS file descriptor.
"A Julia IO that a stream reads from or writes to (the handle of `Siofunctions`)."
mutable struct Sjulia_io
    io::Union{IOStream, IOBuffer}
    close_io::Bool                                     # close the IO with the stream
end

# PORT: SWI-Stream.h io_stream as IOSTREAM
# DIVERGES: see the file's header — the buffer pointers are indices into `mem`, `functions` names a
# function set; the fields of the parts not ported are absent.
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
    IOSTREAM() = new(
        UInt8[], 0, 0, 0, 0, EOF, 0, 0, UInt32(0), IOPOS(), nothing, nothing,
        Smemfunctions,
        ENC_UNKNOWN, 0, SIO_NL_POSIX, 0, nothing, S_UATOMS_ACCEPT
    )
end

# ── the function sets ───────────────────────────────────────────────────────────────────────────
# What upstream's `(*s->functions->read)(s->handle, buf, size)` and the other calls through the
# table do: the function of the stream's set, on its handle. `from` is an index into `mem`.

"Read up to `size` bytes into `mem` at `from`: the count, 0 at end of file, -1 on error."
function S_read(s::IOSTREAM, mem::Vector{UInt8}, from::Int, size::Int)::Int
    h = s.handle
    s.functions == Smemfunctions && h isa memfile &&
        return Sread_memfile(h, mem, from, size)
    s.functions == Siofunctions && h isa Sjulia_io &&
        return Sread_julia_io(h, mem, from, size)
    return Sread_string(s, mem, from, size)
end

"Write the `size` bytes of `mem` from `from`: the count, -1 on error."
function S_write(s::IOSTREAM, mem::Vector{UInt8}, from::Int, size::Int)::Int
    h = s.handle
    s.functions == Smemfunctions && h isa memfile &&
        return Swrite_memfile(h, mem, from, size)
    s.functions == Siofunctions && h isa Sjulia_io &&
        return Swrite_julia_io(h, mem, from, size)
    return Swrite_string(s, mem, from, size)
end

"Close the stream's handle: 0, or -1 on error."
function S_close(s::IOSTREAM)::Int
    h = s.handle
    s.functions == Smemfunctions && h isa memfile && return Sclose_memfile(h)
    s.functions == Siofunctions && h isa Sjulia_io && return Sclose_julia_io(h)
    h isa IOSTREAM && return Sclose_string(h)
    return -1
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

# PORT: pl-stream.c put_code
# DIVERGES: ENC_ANSI, ENC_UTF16* and ENC_WCHAR are refused (not ported).
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
    elseif enc == ENC_UNKNOWN
        return -1
    else
        throw(
            NotPortedError{Nothing}(
                nothing, "put_code: encoding $enc", "UTF-8 only (R1, user 2026-10-07)"
            )
        )
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
"0 if `s`'s encoding can represent `c`, else -1 (pl-stream.c)."
function Scanrepresent(c::Int, s::IOSTREAM)::Int
    enc = s.encoding
    if enc == ENC_OCTET || enc == ENC_ISO_LATIN_1
        return c <= 0xff ? 0 : -1
    elseif enc == ENC_ASCII
        return c < 0x7f ? 0 : -1
    elseif enc == ENC_UTF16BE || enc == ENC_UTF16LE
        return IS_UTF16_SURROGATE(c) ? -1 : 0      # SIZEOF_WCHAR_T > 2
    elseif enc == ENC_WCHAR || enc == ENC_UTF8
        return 0
    end
    throw(
        NotPortedError{Nothing}(
            nothing, "Scanrepresent: encoding $enc", "UTF-8 only (R1, user 2026-10-07)"
        )
    )
end

# PORT: pl-stream.c Sgetcode
# DIVERGES: ENC_ANSI, ENC_UTF16* and ENC_WCHAR are refused (not ported); no `tee`.
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
        else
            throw(
                NotPortedError{Nothing}(
                    nothing, "Sgetcode: encoding $enc", "UTF-8 only (R1, user 2026-10-07)"
                )
            )
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
# DIVERGES: no `SIO_LASTERROR` control (none of the function sets has a message of its own).
"Mark `s` as in error, unless it is already (pl-stream.c)."
function S__seterror(s::IOSTREAM)::Int
    (s.flags & SIO_FERR) != 0 && return 0       # error already set
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
# DIVERGES: no filter streams (`downstream`), no pending exception.
"Clear `s`'s error state (pl-stream.c)."
function Sclearerr(s::IOSTREAM)::Nothing
    if s.magic == SIO_MAGIC
        s.flags &= ~SIO_ERROR_FLAGS
        s.io_errno = 0
        Sseterr(s, UInt32(0), nothing)
    end
    return nothing
end

# PORT: pl-stream.c Sseterr
# DIVERGES: no filter streams (`upstream`).
"Set `s`'s error flags (`SIO_WARN`, `SIO_FERR`) and message (pl-stream.c)."
function Sseterr(s::IOSTREAM, flags::UInt32, message::Union{Nothing, String})::Int
    if s.magic == SIO_MAGIC
        s.flags = (s.flags & ~(SIO_WARN | SIO_FERR)) | flags
        s.message = message
        (s.flags & SIO_WARN) != 0 && @assert s.message !== nothing
        return 0
    end
    return -1
end

# PORT: pl-stream.c Sflush
"Write out `s`'s buffered output: 0, or -1 on error (pl-stream.c)."
function Sflush(s::IOSTREAM)::Int
    if s.buffer != 0 && (s.flags & SIO_OUTPUT) != 0
        S__flushbuf(s) < 0 && return -1
    end
    return 0
end

# ── creating and closing ────────────────────────────────────────────────────────────────────────

# PORT: pl-stream.c Snew
# DIVERGES: a text stream's encoding is UTF-8 (`initEncoding`: no locale); no mutex, no file
# number, no locale.
"A new stream over `handle` with `functions`, its flags `flags` (pl-stream.c)."
function Snew(
    handle::Union{Nothing, memfile, IOSTREAM, Sjulia_io}, flags::UInt32,
    functions::IOFUNCTIONS
)::IOSTREAM
    s = IOSTREAM()
    s.magic = SIO_MAGIC
    s.lastc = EOF
    s.flags = flags
    s.handle = handle
    s.functions = functions
    s.posbuf.lineno = 1
    s.encoding = (flags & SIO_TEXT) != 0 ? ENC_UTF8 : ENC_OCTET
    (flags & SIO_RECORDPOS) != 0 && (s.position = s.posbuf)
    return s
end

# PORT: pl-stream.c S__close
# DIVERGES: no locks, no filter streams, no close hooks; the stream is marked closed and dropped.
"Close `s`: 0, or -1 on error (pl-stream.c)."
function S__close(s::IOSTREAM)::Int
    rval = 0
    s.magic != SIO_MAGIC && return -1           # already closed!?
    (s.flags & SIO_CLOSING) != 0 && return rval # recursive
    s.flags |= SIO_CLOSING
    rval = S__removebuf(s)
    if S_close(s) < 0
        S__seterror(s)
        rval = -1
    end
    s.magic = SIO_CMAGIC
    s.message = nothing
    return rval
end

# PORT: pl-stream.c Sclose
"Close `s`: 0, or -1 on error (pl-stream.c)."
Sclose(s::IOSTREAM)::Int = S__close(s)

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
# owns the stream.
"""
A stream on the user's byte vector `buf` (pl-stream.c): mode `"r"` reads its first `size` bytes,
`"w"` writes into it; ISO Latin-1, as upstream opens it (`Sopen_text` sets the text's encoding).
"""
function Sopen_string(buf::Vector{UInt8}, size::Int, mode::String)::Union{Nothing, IOSTREAM}
    flags = SIO_FBUF | SIO_USERBUF
    s = IOSTREAM()
    s.mem = buf
    s.buffer = 1
    s.bufp = 1
    s.unbuffer = 1
    s.handle = s                                # for Sclose_string()
    s.functions = Sstringfunctions
    s.encoding = ENC_ISO_LATIN_1
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
# DIVERGES: to a Julia IO, where upstream writes a file descriptor.
"Write the `size` bytes of `buf` from `from` to the IO: the count."
function Swrite_julia_io(h::Sjulia_io, buf::Vector{UInt8}, from::Int, size::Int)::Int
    io = h.io
    for k in from:(from + size - 1)
        write(io, buf[k])
    end
    return size
end

# PORT: pl-stream.c Sclose_file as Sclose_julia_io
# DIVERGES: closes the Julia IO only if the stream owns it.
"Close the IO if the stream owns it."
function Sclose_julia_io(h::Sjulia_io)::Int
    h.close_io && close(h.io)
    return 0
end

# PORT: pl-stream.c Sopen_file as Sopen_julia_io
# DIVERGES: a stream on an open Julia IO (a file or a buffer), UTF-8 text, the position recorded,
# where upstream opens a file by name with mode and options.
"A text stream on `io`: mode `\"r\"` or `\"w\"`; closing it closes `io` if `close_io`."
function Sopen_julia_io(
    io::Union{IOStream, IOBuffer}, mode::String, close_io::Bool
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
