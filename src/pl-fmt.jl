# UPSTREAM: swipl-devel src/os/pl-fmt.c @ cbf4e1896275
# UPSTREAM: swipl-devel src/os/pl-fmt.h @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2025, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: CWI, Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# FORMATTED OUTPUT (pl-fmt.c), since O1 (writer A): format/1,2,3 and format_predicate/2,
# current_format_predicate/2. `do_format` walks the format text; a `~` directive writes its argument through
# the column machinery (`format_state`: the stream, the position, the pending fill points), `formatInteger`
# and `formatFloat` write the numbers into a byte buffer first. The redirect part (`setupOutputRedirect`,
# `closeOutputRedirect`, `discardOutputRedirect`, `tellString`, `toldString`) is pl-file.c's: O1B.
#
# DIVERGES (D9): the default C locale only. `~:d` and `~:f` take the C locale (`.` as decimal point, no
# grouping) because a stream here has no locale (`fd->locale`); `~D` and `~I` build their own, as upstream does.
# NOT PORTED: the user-defined directives of `format_predicate/2` (upstream's `GD->format.predicates` table is
# empty unless a program sets it: `format_predicate/2` is refused by name, `current_format_predicate/2` finds
# no entry, and `do_format` goes straight to the built-in directives, which is upstream's behaviour with an
# empty table). The arithmetic and the stream lock calls (`AR_BEGIN`, `Slock`) have no counterpart: no
# arithmetic stack, no threads.

# PORT: pl-fmt.c MAXRUBBER
"The most fill points (`~t`) one column segment holds (pl-fmt.c)."
const MAXRUBBER = 100

# PORT: pl-fmt.c BUFSIZE
"The size of the buffer a sub-format starts with (pl-fmt.c)."
const BUFSIZE = 1024

# PORT: pl-fmt.c DEFAULT
"The numeric argument of a directive when none is given: `INT_MIN` (pl-fmt.c)."
const FMT_DEFAULT = Int(typemin(Int32))

# PORT: pl-fmt.c struct rubber
"A fill point in the pending output: where, how big, and the pad character (pl-fmt.c `struct rubber`)."
mutable struct rubber
    where::Int      # where is rubber in output
    size::Int       # how big should it be
    pad::Int        # padding character (code point)
end

# PORT: pl-fmt.c format_state
# DIVERGES: `buffer` is a byte vector, `rub` grows to `MAXRUBBER` as `~t` asks (upstream: a fixed array).
"The complete state of one `do_format` run (pl-fmt.c `format_state`)."
mutable struct format_state
    out::IOSTREAM               # our output stream
    pos::IOPOS                  # position; pos.linepos is the column
    tab_stop::Int               # Last tab stop
    buffer::Vector{UInt8}       # bin for characters with tabs
    buffered::Int               # characters in buffer
    pending_rubber::Int         # number of not-filled ~t's
    rub::Vector{rubber}
end

# PORT: pl-fmt.c prolog_locale, PL_locale (pl-locale.h)
# DIVERGES: a locale is its three strings (upstream's has more fields and a reference count). `grouping` is
# upstream's `char*`: the group sizes, ended by 0 (`CHAR_MAX`: no more groups), `nothing` for NULL.
"The part of a `PL_locale` that format/2 reads: decimal point, thousands separator, grouping (pl-locale.h)."
struct PL_locale
    decimal_point::Union{Nothing, String}
    thousands_sep::Union{Nothing, String}
    grouping::Union{Nothing, Vector{Int}}
end

"The locale of format/2 when no stream locale is asked for: `.` and no grouping (pl-fmt.c `prolog_locale`)."
const prolog_locale = PL_locale(".", nothing, nothing)

# PORT: pl-fmt.c `static char grouping[] = {3,0}` in do_format
"The grouping of `~D`: groups of three (pl-fmt.c)."
const FMT_GROUPING3 = Int[3, 0]

# PORT: pl-fmt.c FMT_ERROR, FMT_ARG, FMT_ARGC (pl-error.c ERR_FORMAT, ERR_FORMAT_ARG)
# DIVERGES: functions of their own, not `PL_error` codes (no `ERR_FORMAT`, `ERR_FORMAT_ARG` in the enum:
# pl-fmt.c is their only caller) — the branches' `PL_unify_term(formal, format(Msg))` and
# `format_argument_type(Spec, Arg)`; the context names the running predicate, as with `NULL` as `pred`.
"Raise `error(format(Message), context(…))` (pl-error.c `ERR_FORMAT`); `false`."
function PL_format_error(ld::PL_local_data{T}, s::String)::Bool where {T}
    h = _PL_error_open(ld)
    h === nothing && return false
    caller, fid, except, formal, swi = h
    PL_cons_functor(
        ld, formal, _err_functor(ld, :format, 1), _err_atom(ld, mk_sym(T, Symbol(s)))
    )
    return _PL_error_close!(ld, caller, fid, except, formal, swi, "", 0, "")
end

"Raise `error(format_argument_type(Spec, Arg), context(…))` (pl-error.c `ERR_FORMAT_ARG`); `false`."
function PL_format_arg_error(ld::PL_local_data{T}, s::String, arg::term_t)::Bool where {T}
    h = _PL_error_open(ld)
    h === nothing && return false
    caller, fid, except, formal, swi = h
    PL_cons_functor(
        ld, formal, _err_functor(ld, :format_argument_type, 2),
        _err_atom(ld, mk_sym(T, Symbol(s))), arg
    )
    return _PL_error_close!(ld, caller, fid, except, formal, swi, "", 0, "")
end

# PORT: pl-fmt.c COLUMN
"The column `state` is at: the stream layer's line position (pl-fmt.c `COLUMN`)."
@inline COLUMN(state::format_state)::Int = state.pos.linepos

# PORT: pl-fmt.c update_column
"Advance the column over `c` (`Supdatepos`, so that column stops agree with line_position/2); a newline resets the tab stop."
@inline function update_column(state::format_state, c::Int)::Nothing
    Supdatepos(state.pos, c)
    c == Int('\n') && (state.tab_stop = 0)
    return nothing
end

# PORT: pl-fmt.c outchr
"""
Low-level output of the code point `chr`. If there is pending rubber the output is stored in UTF-8 format in
the state's `buffer`; `buffered` is the number of characters in it (pl-fmt.c).
"""
function outchr(state::format_state, chr::Int)::Bool
    if state.pending_rubber != 0
        if chr > 0x7f
            utf8_put_char(state.buffer, chr)
        else
            push!(state.buffer, UInt8(chr))
        end
        state.buffered += 1
    else
        Sputcode(chr, state.out) < 0 && return false
    end
    update_column(state, chr)
    return true
end

# PORT: pl-fmt.c outstring
# DIVERGES: the bytes are `s[from:from+len-1]` of a vector, where upstream passes `char*` and a length.
"Emit the bytes of a 0-terminated string from `sprintf()` on a numeric argument: no fuzz with wide characters (pl-fmt.c)."
function outstring(state::format_state, s::AbstractVector{UInt8}, from::Int, len::Int)::Bool
    e = from + len
    if state.pending_rubber != 0
        append!(state.buffer, view(s, from:(e - 1)))
        state.buffered += len
    else
        for q in from:(e - 1)
            Sputcode(Int(s[q]) & 0xff, state.out) < 0 && return false
        end
    end
    for q in from:(e - 1)
        update_column(state, Int(s[q]) & 0xff)
    end
    return true
end

# PORT: pl-fmt.c oututf8
# DIVERGES: the bytes are `s[from:e-1]` (upstream: a pointer pair).
"Emit the UTF-8 bytes `s[from:e-1]` (pl-fmt.c)."
function oututf8(state::format_state, s::AbstractVector{UInt8}, from::Int, e::Int)::Bool
    if state.pending_rubber == 0
        i = from
        while i < e
            chr = Int(s[i])
            if chr < 0x80
                i += 1
            else
                _, i, chr = _PL__utf8_code_point(s, i, e)
            end
            Sputcode(chr, state.out) < 0 && return false
            update_column(state, chr)
        end
    else
        i = from
        while i < e
            _, i, chr = _PL__utf8_code_point(s, i, e)
            outchr(state, chr) || return false
        end
    end
    return true
end

# PORT: pl-fmt.c oututf80
"Emit the UTF-8 bytes of `s`, a buffer a `formatInteger` or `formatFloat` filled (pl-fmt.c)."
oututf80(state::format_state, s::AbstractVector{UInt8})::Bool = oututf8(state, s, 1, length(s) + 1)

# PORT: pl-fmt.c outtext
# DIVERGES: a UTF-8 text (never canonical here) goes through its code points; `ENC_ISO_LATIN_1` is the
# bytes as upstream (`outstring`), `ENC_WCHAR` the code points.
"Emit the text `txt` holds (pl-fmt.c)."
function outtext(state::format_state, txt::PL_chars_t)::Bool
    if txt.encoding === ENC_ISO_LATIN_1
        return outstring(state, txt.text, 1, txt.length)
    end
    for c in _text_code_points(txt)
        outchr(state, c) || return false
    end
    return true
end

# ── format_predicate/2, current_format_predicate/2 (pl-fmt.c :249-325) ──────────────────────────────

# PORT: pl-fmt.c format_predicate as pl_format_predicate2_va
# (PRED_IMPL("format_predicate", 2, format_predicate, META))
# DIVERGES (D9): refused by name. The table `GD->format.predicates` would hold the predicate of a directive
# character; no program the R2 steps run sets one, and `do_format` ignores the table (see the file header).
"`format_predicate(+Char, :Head)`: refused by name (D9); the call is left to the step that needs user directives."
function pl_format_predicate2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    throw(
        NotPortedError{T}(
            mk_sym(T, :format_predicate), "format_predicate/2 (GD->format.predicates)", "LB5"
        )
    )
end

# PORT: pl-fmt.c current_format_predicate as pl_current_format_predicate2_va
# (PRED_IMPL("current_format_predicate", 2, current_format_predicate, NDET|META))
# DIVERGES (D9): the table is empty, so the first call fails (upstream's `if ( !format_predicates ) fail`).
"`current_format_predicate(?Char, ?Head)`: no user directive is defined (D9), so it fails."
function pl_current_format_predicate2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return FFALSE
end

# ── format/2,3 and their helpers (pl-fmt.c :327-506) ───────────────────────────────────────────────

# PORT: pl-fmt.c format_impl
# DIVERGES: no `Slock(out)`/`Sunlock(out)` (no threads); the format text is not saved off the stacks (the
# text is a Julia vector, a call-back cannot move it). `m` is a module index (0: the context module).
"Format the arguments in the list `Args` through the format text in `format` onto `out` (pl-fmt.c)."
function format_impl(
    ld::PL_local_data{T}, out::IOSTREAM, format::term_t, Args::term_t, m::Int
)::Bool where {T}
    argc = 0
    argv = 0
    args = PL_copy_term_ref(ld, Args)

    fmt = PL_get_text(ld, format, CVT_ATOM | CVT_STRING | CVT_LIST)
    fmt === nothing && return PL_error(ld, "format", 3, "", ERR_TYPE, mk_sym(T, :text), format)

    len = lengthList(ld, args, false)
    if len >= 0
        argc = len
        if argc > 0
            head = PL_new_term_ref(ld)
            argv = PL_new_term_refs(ld, argc)
            n = 0
            while PL_get_list(ld, args, head, args)
                PL_put_term(ld, argv + n, head)
                n += 1
            end
        end
    elseif !PL_is_pair(ld, args)
        argc = 1
        argv = PL_new_term_refs(ld, argc)
        PL_put_term(ld, argv, args)
    else
        return PL_error(ld, ERR_TYPE, mk_sym(T, :list), args)   # PL_type_error("list", args)
    end

    return do_format(ld, out, fmt, argc, argv, m)
end

# PORT: pl-fmt.c format
# DIVERGES: named `format_` (a Julia function `format` is easily shadowed); `m` is an index and the redirect
# context is B's `redir_context` (O1B: pl-file.c `setupOutputRedirect`, `closeOutputRedirect`,
# `discardOutputRedirect`).
"The body of format/2,3: the output redirected to `out` (0: the current output), the arguments in `args` (pl-fmt.c)."
function format_(
    ld::PL_local_data{T}, out::term_t, format::term_t, args::term_t
)::foreign_t where {T}
    gd = _query_gd(ld)
    list = PL_new_term_ref(ld)
    ok, m = PL_strip_module(gd, ld, args, 0, list)
    ok || return FFALSE
    ctx = redir_context()
    rc = setupOutputRedirect(ld, out, ctx, false)
    if rc
        rc = format_impl(ld, ctx.stream, format, list, m)
        if rc
            rc = closeOutputRedirect(ld, ctx)
        else
            discardOutputRedirect(ld, ctx)
        end
    end
    return rc ? FTRUE : FFALSE
end

# PORT: pl-fmt.c format as pl_format2_va
# (PRED_IMPL("format", 2, format, META))
"`format(+Format, :Args)`: formatted output to the current output (pl-fmt.c)."
function pl_format2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    return format_(ld, 0, A1, A2)
end

# PORT: pl-fmt.c format as pl_format3_va
# (PRED_IMPL("format", 3, format, META))
"`format(+Output, +Format, :Args)`: formatted output to a stream, or to `atom(A)`, `string(S)`, `codes(C)` … (pl-fmt.c)."
function pl_format3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    return format_(ld, A1, A2, A3)
end

# PORT: pl-fmt.c get_chr_from_text, text_next_code
# DIVERGES: the format text is its code point vector, so a surrogate pair is no case; a read past the end is
# the terminating NUL of upstream's C string (0).
"The code point at the 0-based index `i` of the format text `fmt`; 0 past its end (pl-fmt.c `get_chr_from_text`)."
@inline get_chr_from_text(fmt::Vector{Int}, i::Int)::Int =
    (i >= 0 && i < length(fmt)) ? @inbounds(fmt[i + 1]) : 0

# PORT: pl-fmt.c sub_state
"The state of a call-back whose output is a sub-format: the buffer it writes to, or the stream to restore (pl-fmt.c)."
mutable struct sub_state
    bufp::Base.RefValue{Union{Nothing, Vector{UInt8}}}
    sizep::Base.RefValue{Int}
    fstate::format_state
    old_stream::Union{Nothing, IOSTREAM}
end

# PORT: pl-fmt.c prepare_sub_format
# DIVERGES: the state is created here (upstream fills a caller's stack struct).
"""
Start the output of a call-back (`~p`, `~w`, `~@` …): when no rubber is pending and the stream's column is the
format's, the call-back writes to `fd` directly; otherwise to a string (pl-fmt.c).
"""
function prepare_sub_format(
    ld::PL_local_data{T}, fstate::format_state, fd::IOSTREAM
)::sub_state where {T}
    state = sub_state(Ref{Union{Nothing, Vector{UInt8}}}(nothing), Ref(0), fstate, nothing)
    if fstate.pending_rubber == 0 && fd.position !== nothing &&
       fd.position.linepos == COLUMN(fstate)
        state.old_stream = Scurout(ld)
        ld.IO_streams[SNO_CURRENT_OUTPUT + 1] = fd      # Scurout = fd
    else
        state.old_stream = nothing
        tellString(ld, state.bufp, state.sizep, ENC_UTF8)
        if (fd.flags & SIO_ISATTY) != 0
            s = Scurout(ld)
            s.flags |= SIO_ISATTY
        end
    end
    return state
end

# PORT: pl-fmt.c end_sub_format
"Close the output of a call-back; `rc` is its result. A string output is written on, and the column moved (pl-fmt.c)."
function end_sub_format(ld::PL_local_data{T}, state::sub_state, rc::Bool)::Bool where {T}
    sub = Scurout(ld).position
    lp = sub.linepos
    if state.old_stream !== nothing
        if rc
            p = state.fstate.pos
            p.byteno = sub.byteno                       # also takes the escape state
            p.charno = sub.charno
            p.lineno = sub.lineno
            p.linepos = sub.linepos
            p.esc_state = sub.esc_state
        end
        ld.IO_streams[SNO_CURRENT_OUTPUT + 1] = state.old_stream
    else
        toldString(ld)
        if rc
            c0 = COLUMN(state.fstate)
            rc = oututf8(state.fstate, state.bufp[]::Vector{UInt8}, 1, state.sizep[] + 1)
            state.fstate.pos.linepos = c0 + lp
        end
    end
    return rc
end

# PORT: pl-fmt.c get_int_expression
# DIVERGES: no `clearNumber` (no GMP handles to free); `isIntegerNumber` is the type test.
"Read an integer from the term `t`, evaluating it if it is an expression; a bignum that fits is an int64 (pl-fmt.c)."
function get_int_expression(ld::PL_local_data{T}, t::term_t, i::number)::Bool where {T}
    PL_get_number(ld, t, i) || valueExpression(ld, t, i) || return false
    if !(i.type === V_INTEGER || i.type === V_MPZ) && !toIntegerNumber(ld, i, 0)
        return false
    end
    if i.type === V_MPZ
        ok, v = mpz_to_int64(i.mpz)
        if ok
            i.type = V_INTEGER
            i.i = v
        end
    end
    return true
end
