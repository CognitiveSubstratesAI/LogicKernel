# UPSTREAM: swipl-devel src/os/pl-file.c @ cbf4e1896275
# UPSTREAM: swipl-devel src/pl-incl.h @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
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

# PORT: pl-file.c pushOutputContext
# DIVERGES: the context stack is a Vector of the streams (upstream: a linked list of
# `struct output_context`, `LD->IO.output_stack`).
"Make `s` the current output; the old current output waits on the output context stack (pl-file.c)."
function pushOutputContext(ld::PL_local_data, s::IOSTREAM)::Nothing
    _initIO(ld)
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
    0, nothing, false, false, 0, 0, 0, Ref(0), Ref{Union{Nothing, Vector{UInt8}}}(nothing)
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
    _initIO(ld)
    ctx.term = to
    ctx.redirected = redir

    if to == 0
        s = getStream(Scurout(ld)::IOSTREAM)
        s === nothing && return no_stream(ld, to, :current_output)
        ctx.stream = s
        ctx.is_stream = true
    elseif (a = PL_get_atom(ld, to)) !== nothing
        if isTextAtom(a) && sym_key(a) == sym_key(mk_sym(T, :user))
            s = getStream(Suser_output(ld)::IOSTREAM)
            s === nothing && return no_stream(ld, to, :user)
            ctx.stream = s
            ctx.is_stream = true
        else
            s = get_stream_handle(ld, a, SH_OUTPUT | SH_ERRORS)
            s === nothing && return false
            ctx.stream = s
            if (s.flags & SIO_OUTPUT) == 0
                return PL_error(
                    ld, "", 0, "", ERR_PERMISSION, mk_sym(T, :output), mk_sym(T, :stream), to
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
    _initIO(ld)
    s = getStream(Scurout(ld)::IOSTREAM)
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
