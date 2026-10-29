# ORIGINAL: S1's mutant list — no swipl-devel counterpart.
# tools/mutants/S1.py — the mutation battery of S1 (R2: stream blobs, user aliases, open/3,4 and close/1,2; D-0149, design
# evidence/r2/design/flags_rest.md §4 D10), run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The
# format is tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# One mutant per decision of the step: the stream table and the aliases (S1-1…S1-8), the closers (S1-9…S1-16), the handle lookup
# (S1-17…S1-22), openStream's options (S1-23…S1-40), the file layer (S1-41…S1-52), the errors (S1-53…S1-58), the writer and the
# file name (S1-59…S1-65). EQUIVALENT, each with its reason:
#   * `aliasStream`'s release of an alias holder (S1-8): openStream refuses an alias already in a table (permission_error) before
#     it opens the file, so the holder branch has no caller;
#   * `Sacquire` and the `erased` mark (S1-47, S1-48): `erased` is read only by get_stream_handle, and a closed stream's table entry
#     is gone by then (`freeStream`), so its blob is no stream either way;
#   * `set_buffering`'s flush (S1-31): a stream just opened has nothing buffered;
#   * the arm of pl_close that turns a false result into "already closed" when an exception is pending (S1-15): PL_error returns
#     false without raising while an exception is pending, so the answer is the same;
# Hand-run (62 mutants): 57 CAUGHT, 5 EQUIVALENT (S1-8, S1-15, S1-31, S1-47, S1-48); two survivors of run 2 (S1-52, S1-56) were killed by new rows
# (Sopen_file's how string; e33 really ELOOP: _clean had been deleting the loop link before the row ran).
# NOT listed: the EMFILE/ENFILE branch of the file errors — no row reaches it. Refitted after the rebase onto BLOB (304ff92): the
# blob is an atom (`stream_blob`), so the writer, the NUM_OTHER reader, the scan fallback and the payload-key mutants are gone
# (S1-22, S1-64 are new: the blob-type check and the payload decode); the file-name mutants (S1-61, S1-62) sit on Y1's code.
TARGETS = ["test/files/test_open_close_swipl.jl"]
T = TARGETS
F = "src/os/pl-file.jl"
S = "src/os/pl-stream.jl"
E = "src/pl-error.jl"
P = "src/os/pl-files.jl"
MUTANTS = [
    # ---- the stream table and the aliases
    dict(id="S1-1 freeStream keeps the stream's aliases", file=F, targets=T,
         old='''    unaliasStream(gd, s, nothing)
''',
         new='''    nothing
'''),
    dict(id="S1-2 freeStream keeps the stream in the table", file=F, targets=T,
         old='''        gd.stream_table[s.context] = nothing        # deleteHTablePP(streamContext, s)''',
         new='''        nothing                                     # deleteHTablePP(streamContext, s)'''),
    dict(id="S1-3 freeStream keeps the stream's file name", file=F, targets=T,
         old='''    delete!(gd.stream_filenames, s)                 # ctx->filename''',
         new='''    nothing                                         # ctx->filename'''),
    dict(id="S1-4 a closed current output is not put back", file=F, targets=T,
         old='''                ld.IO_streams[i + 1] = Suser_output(ld)
''',
         new='''                nothing
'''),
    dict(id="S1-5 freeStream keeps the alias names", file=F, targets=T,
         old='''        delete!(gd.stream_alias_names, s.context)
''',
         new='''        nothing
'''),
    dict(id="S1-6 a blob's read and write fields are swapped", file=F, targets=T,
         old='''    ref = (s.flags & SIO_INPUT) != 0 ? stream_ref(ctx, 0) : stream_ref(0, ctx)''',
         new='''    ref = (s.flags & SIO_INPUT) != 0 ? stream_ref(0, ctx) : stream_ref(ctx, 0)'''),
    dict(id="S1-7 an alias is not entered in the alias table", file=F, targets=T,
         old='''    gd.stream_aliases[sym_key(name)] = s            # addNewHTableWP(streamAliases, name, s)''',
         new='''    nothing                                         # addNewHTableWP(streamAliases, name, s)'''),
    dict(id="S1-8 aliasStream keeps the alias of its previous holder", file=F, targets=T,
         old='''    sp === nothing || unaliasStream(gd, sp, name)   # ensure name is free (error?)''',
         new='''    nothing                                         # ensure name is free (error?)''',
         equivalent="openStream refuses an alias that is in a table (permission_error(open, source_sink, alias(A))) before it "
                    "opens the file, so aliasStream never meets a holder (src/os/pl-file.jl:1023 openStream)"),
    # ---- the closers
    dict(id="S1-9 closeStream does not free the stream", file=F, targets=T,
         old='''    freeStream(ld, s)
    return rc == 0''',
         new='''    return rc == 0'''),
    dict(id="S1-10 close/1 closes a standard stream", file=F, targets=T,
         old='''    elseif s === Suser_output(ld) || s === Suser_error(ld)
        Sflush(s) < 0 && return streamStatus(ld, s)
        return true
    end''',
         new='''    elseif false
        return true
    end'''),
    dict(id="S1-11 close(S, [force(true)]) does not close", file=F, targets=T,
         old='''            Sflush(s)
            Sclose(s)
            freeStream(ld, s)
''',
         new='''            Sflush(s)
            freeStream(ld, s)
'''),
    dict(id="S1-12 close(S, [force(true)]) of a closed stream fails", file=F, targets=T,
         old='''        s === nothing && return true
        if s === Suser_input(ld)''',
         new='''        s === nothing && return false
        if s === Suser_input(ld)'''),
    dict(id="S1-13 close/2 ignores force", file=F, targets=T,
         old='''    force = vals[1] === true''',
         new='''    force = false'''),
    dict(id="S1-14 a closed stream's second close has no message", file=F, targets=T,
         old='''                ld, "", 0, "already closed", ERR_EXISTENCE, mk_sym(T, :stream), stream''',
         new='''                ld, "", 0, "", ERR_EXISTENCE, mk_sym(T, :stream), stream'''),
    dict(id="S1-15 pl_close raises 'already closed' over a pending exception", file=F, targets=T,
         old='''        if !rc && ld.exception_term == 0''',
         new='''        if !rc''',
         equivalent="PL_error returns false without raising while an exception is pending (pl-error.c: 'do not overrule older "
                    "exception'), so the answer and the ball are the same (src/pl-error.jl:70 _PL_error_open)"),
    dict(id="S1-16 close of a non-stream is not a domain error", file=F, targets=T,
         old='''    a === nothing && return not_a_stream(ld, stream, SH_ALIAS)''',
         new='''    a === nothing && return false'''),
    # ---- the handle lookup
    dict(id="S1-17 a blob's mode is not checked", file=F, targets=T,
         old='''        check_stream_mode(ld, a, s, flags) || return nothing
        s.magic == SIO_MAGIC && return s            # getStream(s)''',
         new='''        s.magic == SIO_MAGIC && return s            # getStream(s)'''),
    dict(id="S1-18 the user aliases are not looked up", file=F, targets=T,
         old='''            stream = get(gd.stream_aliases, sym_key(a), nothing)''',
         new='''            stream = nothing'''),
    dict(id="S1-19 an alias's mode is not checked", file=F, targets=T,
         old='''            if stream !== nothing && stream.magic == SIO_MAGIC
                check_stream_mode(ld, a, stream, flags) || return nothing
                return stream''',
         new='''            if stream !== nothing && stream.magic == SIO_MAGIC
                return stream'''),
    dict(id="S1-20 a stream of no table entry is not a missing stream", file=F, targets=T,
         old='''        if s === nothing || s.erased                # if ( s->erased ) goto noent
            (flags & SH_ERRORS) != 0 && symbol_no_stream(ld, a)
            return nothing
        end
''',
         new='''        if false
            return nothing
        end
'''),
    dict(id="S1-21 the unify gives the blob where the stream has an alias", file=F, targets=T,
         old='''        return PL_unify_atom(ld, t, names[1])''',
         new='''        return unify_stream_ref(ld, t, s)'''),
    dict(id="S1-22 a blob of another type is taken for a stream blob", file=F, targets=T,
         old='''    at.type === stream_blob || return nothing''',
         new='''    nothing'''),
    # ---- openStream's options
    dict(id="S1-23 append opens as write", file=F, targets=T,
         old='''    elseif _sym_is(mname, :append)
        push!(how, 'a')''',
         new='''    elseif _sym_is(mname, :append)
        push!(how, 'w')'''),
    dict(id="S1-24 update opens as write", file=F, targets=T,
         old='''    elseif _sym_is(mname, :update)
        push!(how, 'u')''',
         new='''    elseif _sym_is(mname, :update)
        push!(how, 'w')'''),
    dict(id="S1-25 a standard alias may be reused", file=F, targets=T,
         old='''        standardStreamIndexFromName(ld, alias) >= 0 ||
''',
         new=''''''),
    dict(id="S1-26 a user alias may be reused", file=F, targets=T,
         old='''        standardStreamIndexFromName(ld, alias) >= 0 ||
        haskey(gd.stream_aliases, sym_key(alias))''',
         new='''        standardStreamIndexFromName(ld, alias) >= 0'''),
    dict(id="S1-27 an input stream does not check for a BOM by default", file=F, targets=T,
         old='''    bom == -1 && (bom = _sym_is(mname, :read) ? 1 : 0)''',
         new='''    bom == -1 && (bom = 0)'''),
    dict(id="S1-28 write mode writes no BOM", file=F, targets=T,
         old='''        elseif _sym_is(mname, :write) ||
            ((_sym_is(mname, :append)''',
         new='''        elseif false ||
            ((_sym_is(mname, :append)'''),
    dict(id="S1-29 append writes a BOM into a file that has data", file=F, targets=T,
         old='''&& Ssize(s) == 0)''',
         new='''&& true)'''),
    dict(id="S1-30 type(binary) opens a text stream", file=F, targets=T,
         old='''    _sym_is(type, :binary) && push!(how, 'b')''',
         new='''    nothing'''),
    dict(id="S1-31 set_buffering(false) flushes first", file=F, targets=T,
         old='''        Sflush(s)
        s.flags &= ~abuf
        s.flags |= SIO_NBUF''',
         new='''        s.flags &= ~abuf
        s.flags |= SIO_NBUF''',
         equivalent="the stream is new: nothing is buffered to flush (src/os/pl-file.jl:833 set_buffering, called at :1061 right "
                    "after Sopen_file)"),
    dict(id="S1-32 reposition(false) keeps the position", file=F, targets=T,
         old='''    reposition || (s.position = nothing)''',
         new='''    nothing'''),
    dict(id="S1-33 close_on_abort(false) is ignored", file=F, targets=T,
         old='''    close_on_abort || (s.flags |= SIO_NOCLOSE)''',
         new='''    nothing'''),
    dict(id="S1-34 newline(dos) is posix", file=F, targets=T,
         old='''            fnewline = SIO_NL_DOS''',
         new='''            fnewline = SIO_NL_POSIX'''),
    dict(id="S1-35 newline(detect) is posix", file=F, targets=T,
         old='''            fnewline = SIO_NL_DETECT''',
         new='''            fnewline = SIO_NL_POSIX'''),
    dict(id="S1-36 eof_action(error) sets no error flag", file=F, targets=T,
         old='''        s.flags &= ~SIO_NOFEOF
        s.flags |= SIO_FEOF2ERR''',
         new='''        s.flags &= ~SIO_NOFEOF'''),
    dict(id="S1-37 eof_action(reset) sets no flag", file=F, targets=T,
         old='''        s.flags &= ~SIO_FEOF2ERR
        s.flags |= SIO_NOFEOF''',
         new='''        s.flags &= ~SIO_FEOF2ERR'''),
    dict(id="S1-38 buffer(line) is full", file=F, targets=T,
         old='''        s.flags |= SIO_LBUF
    elseif _sym_is(b, Symbol("false"))''',
         new='''        s.flags |= SIO_FBUF
    elseif _sym_is(b, Symbol("false"))'''),
    dict(id="S1-39 create([execute]) adds the wrong bits", file=F, targets=T,
         old='''                cmode |= 0o111''',
         new='''                cmode |= 0o222'''),
    dict(id="S1-40 create([all]) is 755", file=F, targets=T,
         old='''                cmode |= 0o777''',
         new='''                cmode |= 0o755'''),
    # ---- the stream layer
    dict(id="S1-41 a BOM is not skipped", file=S, targets=T,
         old='''                s.bufp += n
                s.flags |= SIO_BOM''',
         new='''                s.flags |= SIO_BOM'''),
    dict(id="S1-42 a BOM is not flagged", file=S, targets=T,
         old='''                s.flags |= SIO_BOM
                s.position !== nothing''',
         new='''                s.position !== nothing'''),
    dict(id="S1-43 a BOM does not set the encoding", file=S, targets=T,
         old='''                s.encoding = enc
                s.bufp += n''',
         new='''                s.bufp += n'''),
    dict(id="S1-44 SwriteBOM does not flag the stream", file=S, targets=T,
         old='''            s.flags |= SIO_BOM
            return 0
        end
        return -1''',
         new='''            return 0
        end
        return -1'''),
    dict(id="S1-45 update mode truncates", file=S, targets=T,
         old='''create=true, truncate=false)''',
         new='''create=true, truncate=true)'''),
    dict(id="S1-46 append mode does not append", file=S, targets=T,
         old='''            open(path; write=true, create=true, append=true)''',
         new='''            open(path; write=true, create=true)'''),
    dict(id="S1-47 a held reference does not erase a closed stream", file=S, targets=T,
         old='''    s.references == 0 || (s.erased = true)      # else unallocStream(): Julia's GC frees it''',
         new='''    nothing                                     # else unallocStream(): Julia's GC frees it''',
         equivalent="`erased` is read only by get_stream_handle, whose stream comes from the table, and freeStream has cleared "
                    "the table entry of a closed stream (src/os/pl-file.jl:692; read at :310): its blob names no stream either way"),
    dict(id="S1-48 aliasStream takes no reference", file=F, targets=T,
         old='''    Sacquire(s)
    push!(get!(Vector{T}, gd.stream_alias_names, ctx), name)''',
         new='''    push!(get!(Vector{T}, gd.stream_alias_names, ctx), name)''',
         equivalent="as S1-47: the reference decides only `erased`, which nothing reads once the table entry is gone"),
    dict(id="S1-49 a new file keeps the default mode", file=S, targets=T,
         old='''    if op != 'r' && !existed && mode != 0o666           # the mode of a file this call created''',
         new='''    if false                                            # the mode of a file this call created'''),
    dict(id="S1-50 the umask is not applied to the mode", file=S, targets=T,
         old='''            chmod(path, mode & ~_current_umask())''',
         new='''            chmod(path, mode)'''),
    dict(id="S1-51 the mode of m is ignored", file=S, targets=T,
         old='''            mode = parse(Int, how[(i + 1):(i + 3)]; base=8)''',
         new='''            mode = 0o666'''),
    dict(id="S1-52 an unknown how-letter is accepted", file=S, targets=T,
         old='''        else                                                # 'l', 'L' (locks: none) and the rest
            return (nothing, EINVAL)''',
         new='''        else                                                # 'l', 'L' (locks: none) and the rest
            nothing'''),
    # ---- the errors
    dict(id="S1-53 EACCES is an existence error", file=E, targets=T,
         old='''    if errno == EAGAIN || errno == EACCES || errno == EPERM || errno == EROFS ||''',
         new='''    if errno == EAGAIN || errno == EPERM || errno == EROFS ||'''),
    dict(id="S1-54 the default file error is a permission error", file=E, targets=T,
         old='''            ld, formal, _err_functor(ld, :existence_error, 2), _err_atom(ld, type), file''',
         new='''            ld, formal, _err_functor(ld, :permission_error, 2), _err_atom(ld, type), file'''),
    dict(id="S1-55 ENAMETOOLONG is an existence error", file=E, targets=T,
         old='''    elseif errno == ELOOP || errno == ENAMETOOLONG''',
         new='''    elseif errno == ELOOP'''),
    dict(id="S1-56 ELOOP is max_path_length", file=E, targets=T,
         old='''        repr = errno == ELOOP ? :max_symbolic_links : :max_path_length''',
         new='''        repr = :max_path_length'''),
    dict(id="S1-57 the uninstantiation error is a type error", file=E, targets=T,
         old='''        ld, formal, _err_functor(ld, :uninstantiation_error, 1), bound  #   PL_TERM, bound''',
         new='''        ld, formal, _err_functor(ld, :type_error, 1), bound  #   PL_TERM, bound'''),
    dict(id="S1-58 a stream argument that does not unify is not an error", file=F, targets=T,
         old='''    if !rval && !PL_is_variable(ld, t)''',
         new='''    if false'''),
    # ---- the writer and the file name
    dict(id="S1-61 a 0-code in a file name is accepted", file=P, targets=T,
         old='''    if 0x00 in codeunits(name)                                  # strlen(name) != len''',
         new='''    if false                                        # strlen(name) != len'''),
    dict(id="S1-62 a file name has no length limit", file=P, targets=T,
         old='''    if ncodeunits(name) >= PATH_MAX''',
         new='''    if false'''),
    dict(id="S1-64 a stream blob's payload is read as the write side only", file=F, targets=T,
         old='''    return stream_ref(Int(v[1]), Int(v[2]))''',
         new='''    return stream_ref(0, Int(v[2]))'''),
    dict(id="S1-65 a file name is not given to the stream", file=F, targets=T,
         old='''    setFileNameStream(gd, s, mk_sym(T, Symbol(path)))''',
         new='''    nothing'''),
]
