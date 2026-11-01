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
#  - `alias(Std)` of a standard stream name (file:2461-2468 `setStandardStream`, with `LD->prompt.next`): REFUSED
#    (`NotPortedError`), the function belongs to the output-redirection step (landing B);
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

        if standardStreamIndexFromName(ld, alias) >= 0
            throw(
                NotPortedError{T}(
                    alias, "set_stream/2's alias(Std) of a standard stream", "setStandardStream (landing B)"
                )
            )
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
        if s.position !== nothing
            s.position.linepos = lpos
            Sresetesc(s.position)
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
        throw(NotPortedError{T}(mk_sym(T, :locale), "set_stream/2's locale(Locale)", "PL_locale"))
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
# DIVERGES: a stream pair is NOT PORTED (`get_stream_handle` refuses it by name); `PL_get_stream_handle` is
# `term_stream_handle(SH_ERRORS|SH_ALIAS)` (no `SH_NOPAIR`); no lock to release.
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
        i === nothing && return PL_domain_error(ld, "stream_attribute", attr) ? FTRUE : FFALSE
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
            return PL_error(ld, "", 0, "", ERR_PERMISSION, mk_sym(T, :pair), mk_sym(T, :stream), stream) ?
                   FTRUE : FFALSE
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

