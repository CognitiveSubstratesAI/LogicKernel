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
    place::Int      # where is rubber in output
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

# ── do_format (pl-fmt.c :508-1017) ──────────────────────────────────────────────────────────────────

# ORIGINAL (O1A): the `i`-th (0-based) fill point of the state, made when first used (upstream: `rub[MAXRUBBER]`).
"The fill point `i` (0-based) of `state`, allocated on first use."
function _rub!(state::format_state, i::Int)::rubber
    while length(state.rub) <= i
        push!(state.rub, rubber(0, 0, 0))
    end
    return state.rub[i + 1]
end

# PORT: pl-fmt.c NEED_ARG
# (a macro in upstream: `return` from do_format with the error)
@inline _fmt_need_arg(ld::PL_local_data, argc::Int)::Bool =
    argc > 0 || (PL_format_error(ld, "not enough arguments"); false)

# PORT: pl-fmt.c do_format
# DIVERGES: the format text is a vector of code points (`_text_code_points`); the user-defined directive lookup
# of `format_predicates` is left out (empty table, D9); `~@` calls `callProlog` with `PL_Q_PASS_EXCEPTION`, so
# the exception stays pending where upstream (`PL_Q_CATCH_EXCEPTION`) returns it in `ex` and raises it again
# after `end_sub_format`; `~:d` and `~:f` take the C locale (no stream locale); no `AR_BEGIN`/`AR_END`.
"""
    do_format(ld, fd, fmt, argc, argv, m) -> Bool

Format the `argc` arguments in the term references `argv…` through the text `fmt` onto the stream `fd`; `m` is
the module `~@` calls in (pl-fmt.c). An error is raised with the exception set and `false` returned.
"""
function do_format(
    ld::PL_local_data{T}, fd::IOSTREAM, fmttxt::PL_chars_t, argc::Int, argv::term_t, m::Int
)::Bool where {T}
    gd = _query_gd(ld)
    fmt = _text_code_points(fmttxt)
    flen = length(fmt)
    state = format_state(fd, IOPOS(), 0, UInt8[], 0, 0, rubber[])
    here = 0
    rc = true
    if fd.position !== nothing                  # state.pos = *fd->position: also takes the escape state
        p = fd.position
        state.pos = IOPOS(p.byteno, p.charno, p.lineno, p.linepos, p.esc_state)
    end

    while here < flen
        c = get_chr_from_text(fmt, here)
        if c == Int('~')
            arg = FMT_DEFAULT                   # Numeric argument
            mod_colon = false                   # Used colon modifier
            neg = false

            # Get the numeric argument
            here += 1
            c = get_chr_from_text(fmt, here)
            if c == Int('-')
                neg = true
                here += 1
                c = get_chr_from_text(fmt, here)
                isDigitW(c) || return PL_format_error(ld, "invalid argument")
            end
            if isDigitW(c)
                arg = c - Int('0')
                here += 1
                while here < flen
                    c = get_chr_from_text(fmt, here)
                    if isDigitW(c)
                        dw = c - Int('0')
                        arg2 = arg * 10 + dw
                        # upstream detects the wrap of an `int` (see mul64() in pl-arith.c)
                        arg2 > typemax(Int32) && return PL_format_error(ld, "argument overflow")
                        arg = arg2
                        here += 1
                    else
                        neg && (arg = -arg)
                        break
                    end
                end
            elseif c == Int('*')
                _fmt_need_arg(ld, argc) || return false
                i = number()
                if !get_int_expression(ld, argv, i) || i.type !== V_INTEGER || i.i < 0 ||
                   i.i > typemax(Int32)
                    return PL_format_arg_error(ld, string(Char(c)), argv)
                end
                argc -= 1                       # SHIFT
                argv += 1
                arg = Int(i.i)
                here += 1
                c = get_chr_from_text(fmt, here)
            elseif c == Int('`') && here < flen
                here += 1                       # text_next_code: the code point after the quote
                arg = get_chr_from_text(fmt, here)
                here += 1
                c = get_chr_from_text(fmt, here)
            end
            if c == Int(':')
                mod_colon = true
                here += 1
                c = get_chr_from_text(fmt, here)
            end

            # NOT PORTED (D9): the check for a user defined format (`format_predicates`), the table is empty.

            if c == Int('a')                    # atomic
                _fmt_need_arg(ld, argc) || return false
                txt = PL_get_text(ld, argv, CVT_ATOM | CVT_STRING)
                txt === nothing && return PL_format_arg_error(ld, "a", argv)
                argc -= 1
                argv += 1
                outtext(state, txt) || return false
                here += 1
            elseif c == Int('c')                # ~c: character code
                _fmt_need_arg(ld, argc) || return false
                chr = PL_get_integer(ld, argv)
                if chr !== nothing && VALID_CODE_POINT(chr)
                    times = (arg == FMT_DEFAULT ? 1 : arg)
                    argc -= 1
                    argv += 1
                    while times > 0
                        times -= 1
                        outchr(state, chr) || return false
                    end
                else
                    return PL_format_arg_error(ld, "c", argv)
                end
                here += 1
            elseif c == Int('e') || c == Int('E') || c == Int('f') || c == Int('F') ||
                   c == Int('g') || c == Int('G') || c == Int('h') || c == Int('H')
                _fmt_need_arg(ld, argc) || return false
                n = number()
                if !PL_get_number(ld, argv, n)
                    if !valueExpression(ld, argv, n)
                        return PL_format_arg_error(ld, string(Char(c)), argv)   # returns error
                    end
                end
                argc -= 1
                argv += 1
                # `l = fd->locale` for `~:f`: the stream has no locale, D9
                l = prolog_locale
                b = UInt8[]
                rc = formatFloat(ld, l, c, arg, n, b)
                rc && (rc = oututf80(state, b))
                rc || return false
                here += 1
            elseif c == Int('d') || c == Int('D') || c == Int('r') || c == Int('R') ||
                   c == Int('I')
                _fmt_need_arg(ld, argc) || return false
                i = number()
                get_int_expression(ld, argv, i) ||
                    return PL_format_arg_error(ld, string(Char(c)), argv)   # return with error
                argc -= 1
                argv += 1
                b = UInt8[]
                si = false
                if c == Int('d') || c == Int('D')
                    if c == Int('D')
                        l = PL_locale(".", mod_colon ? "_" : ",", FMT_GROUPING3)
                    elseif mod_colon
                        l = prolog_locale       # fd->locale, D9
                    else
                        l = nothing
                    end
                    arg == FMT_DEFAULT && (arg = 0)
                    si = formatInteger(l, arg, 10, true, i, b)
                elseif c == Int('I')
                    g = Int(reinterpret(Int8, UInt8((arg == FMT_DEFAULT ? 3 : arg) & 0xff)))
                    l = PL_locale(nothing, "_", Int[g, 0])
                    si = formatInteger(l, 0, 10, true, i, b)
                else                            # r,R
                    arg == FMT_DEFAULT && (arg = 8)
                    if arg < 2 || arg > 36
                        r = PL_new_term_ref(ld)
                        PL_put_integer(ld, r, arg)
                        PL_error(ld, "", 0, "", ERR_DOMAIN, mk_sym(T, :radix), r)
                        si = false
                    else
                        si = formatInteger(nothing, 0, arg, c == Int('r'), i, b)
                    end
                end
                rc = si ? oututf80(state, b) : false
                rc || return false
                here += 1
            elseif c == Int('s')                # string
                _fmt_need_arg(ld, argc) || return false
                txt = PL_get_text(ld, argv, CVT_ATOM | CVT_LIST | CVT_STRING)
                txt === nothing && return PL_format_arg_error(ld, "s", argv)
                if txt.encoding === ENC_ISO_LATIN_1
                    tlen = txt.length
                    if arg == FMT_DEFAULT
                        arg = tlen
                    elseif arg < 0
                        arg = 0
                    elseif arg < tlen
                        tlen = arg
                        txt = PL_chars_t(txt.text, tlen, txt.encoding, txt.canonical)
                    end
                    rc = outtext(state, txt)
                else
                    cps = _text_code_points(txt)
                    tlen = length(cps)
                    if arg == FMT_DEFAULT
                        arg = tlen
                    elseif arg < 0
                        arg = 0
                    elseif arg < tlen
                        tlen = arg
                    end
                    rc = true
                    for k in 1:tlen
                        rc = outchr(state, cps[k])
                        rc || break
                    end
                end
                npad = arg - tlen
                while rc && npad > 0
                    rc = outchr(state, Int(' '))
                    npad -= 1
                end
                argc -= 1
                argv += 1
                rc || return false
                here += 1
            elseif c == Int('i')                # ignore
                _fmt_need_arg(ld, argc) || return false
                argc -= 1
                argv += 1
                here += 1
            elseif c == Int('k') || c == Int('p') || c == Int('q') || c == Int('w')
                _fmt_need_arg(ld, argc) || return false
                sstate = prepare_sub_format(ld, state, fd)
                r = if c == Int('k')            # write_canonical
                    pl_write_canonical(ld, argv)
                elseif c == Int('p')            # print
                    pl_print(ld, argv)
                elseif c == Int('q')            # writeq
                    pl_writeq(ld, argv)
                else                            # write
                    pl_write(ld, argv)
                end
                rc = end_sub_format(ld, sstate, r != FFALSE)
                rc || return false
                argc -= 1
                argv += 1
                here += 1
            elseif c == Int('W')                # write_term(Value, Options)
                argc < 2 && return PL_format_error(ld, "not enough arguments")
                sstate = prepare_sub_format(ld, state, fd)
                r = pl_write_term3(ld, 0, argv, argv + 1)
                rc = end_sub_format(ld, sstate, r)
                rc || return false
                argc -= 2
                argv += 2
                here += 1
            elseif c == Int('@')
                argc < 1 && return PL_format_error(ld, "not enough arguments")
                sstate = prepare_sub_format(ld, state, fd)
                fid = PL_open_foreign_frame(ld)
                rc = callProlog(gd, ld, m, argv, PL_Q_PASS_EXCEPTION)
                rc && PL_rewind_foreign_frame(ld, fid)
                rc = end_sub_format(ld, sstate, rc)
                rc || return false
                argc -= 1
                argv += 1
                here += 1
            elseif c == Int('~')                # ~
                outchr(state, Int('~')) || return false
                here += 1
            elseif c == Int('n')                # \n
                arg == FMT_DEFAULT && (arg = 1)
                while arg > 0
                    arg -= 1
                    outchr(state, Int('\n')) || return false
                end
                here += 1
            elseif c == Int('N')                # \n if not on newline
                if COLUMN(state) != 0
                    outchr(state, Int('\n')) || return false
                end
                here += 1
            elseif c == Int('t')                # insert tab
                state.pending_rubber >= MAXRUBBER && return PL_format_error(ld, "Too many tab stops")
                r = _rub!(state, state.pending_rubber)
                r.place = state.buffered
                r.pad = (arg == FMT_DEFAULT ? Int(' ') : arg)
                r.size = 0
                state.pending_rubber += 1
                here += 1
            elseif c == Int('|') || c == Int('+')   # set tab, tab relative
                if c == Int('|') && arg == FMT_DEFAULT
                    arg = COLUMN(state)
                end
                arg == FMT_DEFAULT && (arg = 8)
                stop = (c == Int('+') ? state.tab_stop + arg : arg)
                if stop < COLUMN(state) && mod_colon
                    nl_and_reindent =
                        state.pending_rubber != 0 ? state.rub[state.pending_rubber].pad : Int(' ')
                else
                    nl_and_reindent = 0
                end
                if state.pending_rubber == 0    # nothing to distribute
                    r = _rub!(state, 0)
                    r.place = state.buffered
                    r.pad = Int(' ')
                    state.pending_rubber += 1
                end
                distribute_rubber(state.rub, state.pending_rubber, stop - COLUMN(state))
                emit_rubber(state) || return false
                if nl_and_reindent != 0
                    Sputcode(Int('\n'), state.out) < 0 && return false
                    update_column(state, Int('\n'))
                    r = _rub!(state, 0)
                    r.place = state.buffered
                    r.pad = nl_and_reindent
                    state.pending_rubber += 1
                    distribute_rubber(state.rub, state.pending_rubber, stop - COLUMN(state))
                    emit_rubber(state) || return false
                end
                state.pos.linepos = stop
                state.tab_stop = stop
                here += 1
            else
                ex = PL_new_term_ref(ld)
                PL_put_atom(ld, ex, codeToAtom(T, c))
                return PL_error(
                    ld, "format", 2, "", ERR_EXISTENCE, mk_sym(T, :format_character), ex
                )
            end
        else
            outchr(state, c) || return false    # text_next_code: one code point per element here
            here += 1
        end
    end

    if state.pending_rubber != 0                # not closed ~t: flush out
        emit_rubber(state) || return false
    end
    argc != 0 && return PL_format_error(ld, "too many arguments")
    return rc
end

# ── rubber: distribute_rubber, emit_rubber (pl-fmt.c :1018-1110) ───────────────────────────────────

# PORT: pl-fmt.c distribute_rubber
"Give the `rn` fill points of `r` a share of `space`: equal sizes, the rest from the last one backwards (pl-fmt.c)."
function distribute_rubber(r::Vector{rubber}, rn::Int, space::Int)::Nothing
    if space > 0
        s = space ÷ rn
        for n in 1:rn                           # give them equal size
            r[n].size = s
        end
        space -= s * rn                         # distribute from the center
        n = rn
        while space != 0
            r[n].size += 1
            n -= 1
            space -= 1
        end
    else
        for n in 1:rn                           # set all rubber to 0
            r[n].size = 0
        end
    end
    return nothing
end

# PORT: pl-fmt.c emit_rubber
"Write the buffered output with the fill points expanded to their pad characters; the state is then empty (pl-fmt.c)."
function emit_rubber(state::format_state)::Bool
    buf = state.buffer
    s = 1
    e = length(buf) + 1
    ri = 1
    rn = state.pending_rubber
    j = 0
    while s <= e
        while rn != 0 && state.rub[ri].place == j
            r = state.rub[ri]
            for _ in 1:r.size
                Sputcode(r.pad, state.out) < 0 && return false
            end
            ri += 1
            rn -= 1
        end
        if s < e
            _, s, chr = _PL__utf8_code_point(buf, s, e)
            Sputcode(chr, state.out) < 0 && return false
        else
            break
        end
        j += 1
    end
    empty!(state.buffer)
    state.buffered = 0
    state.pending_rubber = 0
    return true
end

# ── formatInteger and its helpers (pl-fmt.c :1110-1440; the C locale, D9) ──────────────────────────

# PORT: pl-fmt.c lappend
# DIVERGES: the text is a `String`; reversing all its bytes is upstream's per-character reversal.
"Append the locale string `l` (or the character `def` when none) to `out` reversed, as `formatInteger` builds its digits backwards (pl-fmt.c)."
function lappend(l::Union{Nothing, String}, def::Char, out::Vector{UInt8})::Nothing
    if l !== nothing
        append!(out, reverse(codeunits(l)))
    else
        push!(out, UInt8(def))
    end
    return nothing
end

# ORIGINAL (O1A): pl-ctype.h `digitName`, which pl-fmt.c uses: the character for the digit value `n`.
"The character of the digit value `n` (0..35), lowercase letters when `smll` (pl-ctype.h `digitName`)."
digitName(n::Int, smll::Bool)::UInt8 =
    n <= 9 ? UInt8('0') + UInt8(n) : (UInt8(smll ? 'a' : 'A') + UInt8(n - 10))

# PORT: pl-fmt.c formatInteger
# DIVERGES: `out` is a byte vector without the terminating NUL, the result is whether it succeeded; a number
# of more fraction digits than a bignum has (`~25d` of 2^64) pads with '0' where upstream reads before the
# digits. `divv` is upstream's `div`; the `grouping` pointer is the index `gi`.
"""
    formatInteger(locale, divv, radix, smll, i, out) -> Bool

Format the integer `i` into `out`. `divv` is for fixed point numbers (the decimal point goes `divv` digits from
the end), `radix` is the base, `smll` selects lowercase letters for digit values above 9 (pl-fmt.c).
"""
function formatInteger(
    locale::Union{Nothing, PL_locale}, divv::Int, radix::Int, smll::Bool, i::number,
    out::Vector{UInt8}
)::Bool
    grouping = nothing
    gi = 1
    if locale === nothing
        locale = prolog_locale
    elseif locale.grouping !== nothing && !isempty(locale.grouping) && locale.grouping[1] != 0 &&
           locale.thousands_sep !== nothing && !isempty(locale.thousands_sep)
        grouping = locale.grouping
    end
    if i.type === V_INTEGER
        n = i.i
        if n == 0 && divv == 0
            push!(out, UInt8('0'))
        else
            before = false                      # before decimal point
            gsize = 0
            negative = n < 0
            while n != 0 || divv >= 0
                d0 = divv
                divv -= 1
                if d0 == 0 && !before
                    isempty(out) || lappend(locale.decimal_point, '.', out)
                    before = true
                    grouping === nothing || (gsize = grouping[gi])
                end
                dweight = !negative ? Int(rem(n, radix)) : -Int(rem(n, -radix))
                push!(out, digitName(dweight, smll))
                n = div(n, radix)
                gsize -= 1
                if gsize == 0 && n != 0
                    lappend(locale.thousands_sep, ',', out)
                    if grouping[gi + 1] == 0
                        gsize = grouping[gi]
                    elseif grouping[gi + 1] == 127      # CHAR_MAX
                        gsize = 0
                    else
                        gi += 1
                        gsize = grouping[gi]
                    end
                end
            end
            negative && push!(out, UInt8('-'))
        end
        reverse!(out)                           # revert_string
        return true
    elseif i.type === V_MPZ
        buf = string(i.mpz; base = radix)
        (!smll && radix > 10) && (buf = uppercase(buf))
        if grouping !== nothing || divv > 0
            before = false                      # before decimal point
            gsize = 0
            e = length(buf)
            while e >= 1 || divv >= 0
                d0 = divv
                divv -= 1
                if d0 == 0 && !before
                    isempty(out) || lappend(locale.decimal_point, '.', out)
                    before = true
                    grouping === nothing || (gsize = grouping[gi])
                end
                push!(out, e >= 1 ? UInt8(buf[e]) : UInt8('0'))
                e -= 1
                gsize -= 1
                if gsize == 0 && e >= 1 && buf[e] != '-'
                    lappend(locale.thousands_sep, ',', out)
                    if grouping[gi + 1] == 0
                        gsize = grouping[gi]
                    elseif grouping[gi + 1] == 127      # CHAR_MAX
                        gsize = 0
                    else
                        gi += 1
                        gsize = grouping[gi]
                    end
                end
            end
            reverse!(out)
        else
            append!(out, codeunits(buf))
        end
        return true
    end
    return false                                # V_MPQ, V_FLOAT: not integers (assert(0) upstream)
end

# PORT: pl-fmt.c countGroups
"How many separators `len` digits take under the `grouping` (pl-fmt.c)."
function countGroups(grouping::Vector{Int}, len::Int)::Int
    groups = 0
    gi = 1
    gsize = grouping[gi]
    while len > 0
        len -= gsize
        len > 0 && (groups += 1)
        if grouping[gi + 1] == 0
            len > 1 && (groups += (len - 1) ÷ grouping[gi])
            return groups
        elseif grouping[gi + 1] == 127          # CHAR_MAX
            return groups
        else
            gi += 1
            gsize = grouping[gi]
        end
    end
    return groups
end

# PORT: pl-fmt.c ths_to_utf8
# DIVERGES: the result is the bytes, or `nothing` when `s` does not fit `len` bytes (upstream: a 0/1 result).
"The UTF-8 bytes of the locale string `s`, or `nothing` if it does not fit in a buffer of `len` bytes (pl-fmt.c)."
function ths_to_utf8(s::String, len::Int)::Union{Nothing, Vector{UInt8}}
    u8 = UInt8[]
    for ch in s
        length(u8) >= len - 7 && return nothing
        append!(u8, codeunits(string(ch)))
    end
    return u8
end

# PORT: pl-fmt.c utf8_dp
"The decimal point of `l` as UTF-8 bytes (`.` when it has none), or `nothing` if it is too long (pl-fmt.c)."
utf8_dp(l::PL_locale)::Union{Nothing, Vector{UInt8}} =
    l.decimal_point !== nothing ? ths_to_utf8(l.decimal_point, 20) : UInt8[UInt8('.')]

# PORT: pl-fmt.c find_decimal_point
# DIVERGES: returns the 1-based start and the length in bytes of the separator in `s`, or `nothing`.
"Where the decimal separator of the number in `s` is: the non-digit run between its digit sequences, `nothing` if none (pl-fmt.c)."
function find_decimal_point(s::Vector{UInt8})::Union{Nothing, Tuple{Int, Int}}
    n = length(s)
    i = 1
    if n >= 1 && (s[1] == UInt8('-') || s[1] == UInt8('+'))
        i += 1
    end
    e = i
    while e <= n && isDigit(Int(s[e]))
        e += 1
    end
    e == i && return nothing                    # inf, nan, ...
    p = e
    while p <= n && !isDigit(Int(s[p])) && s[p] != UInt8('e') && s[p] != UInt8('E')
        p += 1
    end
    (p == e || p > n || !isDigit(Int(s[p]))) && return nothing
    return (e, p - e)
end

# PORT: pl-fmt.c localizeDecimalPoint
"Replace the decimal point the number printing code wrote in `b` by the one of `locale` (pl-fmt.c)."
function localizeDecimalPoint(locale::PL_locale, b::Vector{UInt8})::Bool
    sep = find_decimal_point(b)
    sep === nothing && return true
    dp = utf8_dp(locale)
    dp === nothing && return false
    splice!(b, sep[1]:(sep[1] + sep[2] - 1), dp)
    return true
end

# PORT: pl-fmt.c groupDigits
"Put the thousands separator of `locale` into the integer part of the number in `b` (pl-fmt.c)."
function groupDigits(locale::PL_locale, b::Vector{UInt8})::Bool
    ts = locale.thousands_sep
    gr = locale.grouping
    if ts !== nothing && !isempty(ts) && gr !== nothing && !isempty(gr) && gr[1] != 0
        n = length(b)
        s = 1
        n >= 1 && b[1] == UInt8('-') && (s += 1)
        e = s
        while e <= n && isDigit(Int(b[e]))
            e += 1
        end
        groups = countGroups(gr, e - s)
        if groups > 0
            gi = 1
            gsize = gr[gi]
            ths = ths_to_utf8(ts, 20)
            ths === nothing && return false
            rev = UInt8[]
            k = e - 1
            while k >= s
                push!(rev, b[k])
                k -= 1
                gsize -= 1
                if gsize == 0 && k >= s
                    append!(rev, reverse(ths))
                    if gr[gi + 1] == 0
                        gsize = gr[gi]
                    elseif gr[gi + 1] == 127    # CHAR_MAX
                        gsize = 0
                    else
                        gi += 1
                        gsize = gr[gi]
                    end
                end
            end
            nb = vcat(b[1:(s - 1)], reverse(rev), b[e:n])
            empty!(b)
            append!(b, nb)
        end
    end
    return true
end

# PORT: gmp mpz_sizeinbase(z, 10)
# GMP answers `floor(bits * log10(2)) + 1` for the number of bits `z` has: exact or one too big (8 gives 2);
# the exponent guesses of formatFloat below correct for it, as upstream's do.
"The size of the magnitude of `z` in decimal digits as GMP's `mpz_sizeinbase(z, 10)` counts it (an upper bound by one)."
function mpz_sizeinbase10(z::BigInt)::Int
    z == 0 && return 1
    return floor(Int, ndigits(z; base = 2) * 0.30102999566398119521373889472449) + 1
end

"`10^e` for `e >= 0` (`mpz_ui_pow_ui(r, 10, e)`)."
_fmt_pow10(e::Int)::BigInt = BigInt(10)^e

# PORT: pl-fmt.c formatFloat, label print_mpz_f (V_MPZ and V_MPQ `~Nf`)
# DIVERGES: the string is built whole; upstream grows the buffer and moves the digits with memmove/memset.
"""
    _fmt_print_mpz_f!(out, t1, neg, arg)

Write `t1` (the magnitude of the number scaled by `10^arg`) as a fixed point number with `arg` fraction digits,
zero padded on the left to at least `arg+1` digits (pl-fmt.c `print_mpz_f`). `neg` puts the `-` in front, also
for a magnitude that rounded to 0.
"""
function _fmt_print_mpz_f!(out::Vector{UInt8}, t1::BigInt, neg::Bool, arg::Int)::Nothing
    digits = t1 == 0 ? "" : string(t1)
    nd = ncodeunits(digits)
    padding = nd <= arg ? arg - nd + 1 : 0
    s = "0"^padding * digits
    if arg > 0
        n = ncodeunits(s)
        s = s[1:(n - arg)] * "." * s[(n - arg + 1):n]       # localizeDecimalPoint() follows
    end
    neg && (s = "-" * s)
    append!(out, codeunits(s))
    return nothing
end

# PORT: pl-fmt.c formatFloat, label print_mpz_e (V_MPZ and V_MPQ `~Ne`)
# DIVERGES: as `_fmt_print_mpz_f!`. Upstream returns from here: no localizeDecimalPoint, no groupDigits; the
# decimal point is the first BYTE of the locale's (`decimal_point[0]`).
"""
    _fmt_print_mpz_e!(out, locale, t1, how, ex, arg, neg)

Write `t1` (all the significant digits, `arg+1` of them) as `d.ddde+XX` with the exponent `ex` (pl-fmt.c).
"""
function _fmt_print_mpz_e!(
    out::Vector{UInt8}, locale::Union{Nothing, PL_locale}, t1::BigInt, how::Int, ex::Int,
    arg::Int, neg::Bool
)::Nothing
    digits = string(t1)                                     # "%Zd"
    t1 == 0 && (digits = "0"^arg * digits)
    dpb = UInt8('.')
    if locale !== nothing && locale.decimal_point !== nothing && !isempty(locale.decimal_point)
        dpb = codeunit(locale.decimal_point, 1)
    end
    neg && push!(out, UInt8('-'))
    d = codeunits(digits)
    push!(out, d[1])
    if arg > 0
        push!(out, dpb)
    end
    append!(out, @view d[2:end])
    push!(out, UInt8(how))
    push!(out, ex < 0 ? UInt8('-') : UInt8('+'))            # "%+03d"
    append!(out, codeunits(lpad(string(abs(ex)), 2, '0')))
    return nothing
end

# PORT: pl-fmt.c formatFloat, case V_MPZ, `e` and `E`
"The `~Ne` of a big integer (pl-fmt.c): round to `arg+1` significant digits, then `_fmt_print_mpz_e!`."
function _fmt_mpz_e!(
    out::Vector{UInt8}, locale::Union{Nothing, PL_locale}, how::Int, arg::Int, z::BigInt
)::Nothing
    neg = z < 0
    t1 = abs(z)
    ex = 0
    if t1 != 0
        ex = mpz_sizeinbase10(t1) - 1                       # guess exponent
        _fmt_pow10(ex) > t1 && (ex -= 1)                    # correct exponent
        if ex > arg
            t2 = _fmt_pow10(ex - arg - 1)
            t1 = div(t1, t2)                                # mpz_tdiv_q
            t1 += 5
            t1 = div(t1, 10)
        else
            t1 *= _fmt_pow10(arg - ex)
        end
    end
    _fmt_print_mpz_e!(out, locale, t1, how, ex, arg, neg)
    return nothing
end

# PORT: pl-fmt.c formatFloat, case V_MPQ, `e` and `E`
"The `~Ne` of a rational (pl-fmt.c): the exponent guess with its corrections, round, then `_fmt_print_mpz_e!`."
function _fmt_mpq_e!(
    out::Vector{UInt8}, locale::Union{Nothing, PL_locale}, how::Int, arg::Int, q::Rational{BigInt}
)::Nothing
    n = numerator(q)
    d = denominator(q)
    ge1 = abs(n) >= d
    local ex::Int
    if ge1
        t1 = div(n, d)
        ex = mpz_sizeinbase10(t1) - 1                       # guess exponent
        _fmt_pow10(ex) > abs(t1) && (ex -= 1)               # correct exponent
    else
        t1 = div(d, abs(n))
        ex = -mpz_sizeinbase10(t1)                          # guess exponent
        t2 = _fmt_pow10(abs(ex) - 1)
        t2 == abs(t1) && Rational{BigInt}(t1) == inv(q) && (ex += 1)
        t2 > abs(t1) && (ex += 1)                           # correct exponent
    end
    t1 = _fmt_pow10(abs(arg - ex))
    if ge1 && ex > arg
        t1 = div(n, t1)
    else
        t1 = n * t1
    end
    t2 = div(d, 2)
    neg = q < 0
    t1 = neg ? t1 - t2 : t1 + t2
    t1 = abs(div(t1, d))
    if _fmt_pow10(arg + 1) == t1
        t1 = div(t1, 10)
        ex += 1
    end
    _fmt_print_mpz_e!(out, locale, t1, how, ex, arg, neg)
    return nothing
end

# PORT: pl-fmt.c formatFloat, cases V_MPZ and V_MPQ, `f` and `F`
"""
    _fmt_mpq_f!(out, q, arg)
    _fmt_mpz_f!(out, z, arg)

The `~Nf` of a rational or a big integer (pl-fmt.c, "courtesy of Jan Burse"): `(n*10^arg + d//2) // d`
with the point `arg` digits from the end; a negative number rounds away from zero and keeps its `-`.
"""
function _fmt_mpq_f!(out::Vector{UInt8}, q::Rational{BigInt}, arg::Int)::Nothing
    d = denominator(q)
    t1 = numerator(q) * _fmt_pow10(arg)
    t2 = div(d, 2)
    neg = q < 0
    t1 = neg ? t1 - t2 : t1 + t2
    t1 = abs(div(t1, d))
    _fmt_print_mpz_f!(out, t1, neg, arg)
    return nothing
end

function _fmt_mpz_f!(out::Vector{UInt8}, z::BigInt, arg::Int)::Nothing
    t1 = z * _fmt_pow10(arg)
    _fmt_print_mpz_f!(out, abs(t1), t1 < 0, arg)
    return nothing
end

# PORT: gmp mpf_init2 + mpf_set_z / mpf_set_q, for formatFloat's `g` paths
# DIVERGES: the mpf is a truncated exact rational. GMP keeps `prec+1` limbs of 64 bits, `prec` being
# `(max(53, bits)+127) div 64`: an integer loses its low limbs, a rational is divided to that many limbs. The
# rational's cut is placed by bit lengths, not by limb boundaries; it differs from GMP's only for a value within
# 2^-(64*prec) of a decimal rounding boundary. (A dyadic tie stays exact, a tie like 0.995 falls just below.)
"The value of `mpf_init2(bits)` followed by `mpf_set_z(z)`, `z > 0`, as an exact rational."
function _fmt_mpf_set_z(bits::Int, z::BigInt)::Rational{BigInt}
    keep = (max(53, bits) + 127) ÷ 64 + 1
    nl = cld(ndigits(z; base = 2), 64)
    if nl > keep
        sh = 64 * (nl - keep)
        z = (z >> sh) << sh
    end
    return Rational{BigInt}(z)
end

"The value of `mpf_init2(bits)` followed by `mpf_set_q(q)`, `q > 0`, as an exact rational."
function _fmt_mpf_set_q(bits::Int, q::Rational{BigInt})::Rational{BigInt}
    keep = (max(53, bits) + 127) ÷ 64 + 1
    n = numerator(q)
    d = denominator(q)
    s = 64 * keep - (ndigits(n; base = 2) - ndigits(d; base = 2))
    m = s >= 0 ? div(n << s, d) : div(n, d << (-s))
    return s >= 0 ? m // (BigInt(1) << s) : (m << (-s)) // BigInt(1)
end

"`10^e` as an exact rational, any sign of `e`."
_fmt_pow10q(e::Int)::Rational{BigInt} =
    e >= 0 ? Rational{BigInt}(_fmt_pow10(e)) : Rational{BigInt}(BigInt(1), _fmt_pow10(-e))

"""
    _fmt_round_sig(v, P) -> (digits, X)

The `P` significant digits of `v > 0` rounded half up (GMP's `mpf_get_str` looks at the next digit only) and the
decimal exponent `X` of the first of them: `v` is about `d.ddd * 10^X`.
"""
function _fmt_round_sig(v::Rational{BigInt}, P::Int)::Tuple{String, Int}
    X = v >= 1 ? ndigits(div(numerator(v), denominator(v))) - 1 : -ndigits(div(denominator(v), numerator(v)))
    while _fmt_pow10q(X) > v
        X -= 1
    end
    while _fmt_pow10q(X + 1) <= v
        X += 1
    end
    w = v * _fmt_pow10q(P - 1 - X) + 1 // 2
    r = fld(numerator(w), denominator(w))
    if ndigits(r) > P
        r = div(r, 10)
        X += 1
    end
    return (string(r), X)
end

# PORT: gmp gmp_snprintf "%.<P>F{g,G}" of an mpf (doprnt.c: the C `%g` rules)
"""
    _fmt_print_mpf_g!(out, v, neg, how, arg)

Write `v >= 0` as `%.<arg>g` does, `arg` 0 meaning 1: `P` significant digits, the exponent form when the
exponent is below -4 or at least `P`, trailing zeros and a bare point removed.
"""
function _fmt_print_mpf_g!(out::Vector{UInt8}, v::Rational{BigInt}, neg::Bool, how::Int, arg::Int)::Nothing
    P = max(arg, 1)
    neg && push!(out, UInt8('-'))
    if v == 0
        push!(out, UInt8('0'))
        return nothing
    end
    digits, X = _fmt_round_sig(v, P)
    if X < -4 || X >= P
        frac = rstrip(SubString(digits, 2), '0')
        isempty(frac) ? push!(out, UInt8(digits[1])) :
            append!(out, codeunits(string(digits[1], '.', frac)))
        push!(out, UInt8(how == Int('G') ? 'E' : 'e'))
        push!(out, X < 0 ? UInt8('-') : UInt8('+'))
        append!(out, codeunits(lpad(string(abs(X)), 2, '0')))
    else
        local ip::String, fp::String
        if X >= 0
            ip = digits[1:(X + 1)]
            fp = String(rstrip(SubString(digits, X + 2), '0'))
        else
            ip = "0"
            fp = String(rstrip("0"^(-X - 1) * digits, '0'))
        end
        append!(out, codeunits(isempty(fp) ? ip : string(ip, '.', fp)))
    end
    return nothing
end

# PORT: pl-fmt.c formatFloat, case V_MPZ `g`/`G` (mpf_init2(arg*4), mpf_set_z) and case V_MPQ `g`/`G`
# (mpf_init2(bits of the integer part + 4*arg), mpf_set_q)
"The `~Ng` of a big integer (pl-fmt.c): `%.<arg>g` of an mpf holding it."
function _fmt_mpz_g!(out::Vector{UInt8}, how::Int, arg::Int, z::BigInt)::Nothing
    _fmt_print_mpf_g!(out, _fmt_mpf_set_z(arg * 4, abs(z)), z < 0, how, arg)
    return nothing
end

"The `~Ng` of a rational (pl-fmt.c)."
function _fmt_mpq_g!(out::Vector{UInt8}, how::Int, arg::Int, q::Rational{BigInt})::Nothing
    iv = div(numerator(q), denominator(q))                  # mpz_set_q: truncates
    fbits = ndigits(abs(iv); base = 2) + 4 * arg            # mpz_sizeinbase(iv, 2)
    _fmt_print_mpf_g!(out, _fmt_mpf_set_q(fbits, abs(q)), q < 0, how, arg)
    return nothing
end

# PORT: C snprintf("%.<arg>{e,E,f,F,g,G}", f), the V_FLOAT tail of pl-fmt.c formatFloat
# DIVERGES: Julia's `Base.Ryu` (exact, ties to even: what glibc prints) in place of the C library; the
# infinities and NaN are spelled as C does (`inf`, `-nan`, `INF` for the capitals).
"The text `snprintf(\"%.<arg>{how}\", f)` gives, `how` one of `eEfFgG`."
function _fmt_c_printf_float(f::Float64, how::Int, arg::Int)::String
    upper = how == Int('E') || how == Int('F') || how == Int('G')
    if !isfinite(f)
        s = isnan(f) ? "nan" : "inf"
        s = signbit(f) ? "-" * s : s
        return upper ? uppercase(s) : s
    end
    expch = UInt8(upper ? 'E' : 'e')
    if how == Int('f') || how == Int('F')
        return Base.Ryu.writefixed(f, arg)
    elseif how == Int('e') || how == Int('E')
        return Base.Ryu.writeexp(f, arg, false, false, false, expch)
    end
    P = max(arg, 1)                                         # %g: precision 0 is 1
    es = Base.Ryu.writeexp(f, P - 1, false, false, false, expch)
    ei = findlast(c -> c == Char(expch), es)::Int
    X = parse(Int, SubString(es, ei + 1))                   # the exponent after rounding
    if X < -4 || X >= P
        mant = String(SubString(es, 1, ei - 1))
        occursin('.', mant) && (mant = String(rstrip(rstrip(mant, '0'), '.')))
        return string(mant, SubString(es, ei))
    end
    s = Base.Ryu.writefixed(f, P - 1 - X)
    occursin('.', s) && (s = String(rstrip(rstrip(s, '0'), '.')))
    return s
end

# PORT: pl-fmt.c formatFloat
# DIVERGES: appends to `out` (the caller's empty vector) with no terminating NUL; the result is `false` with
# an exception raised where upstream returns NULL. O_GMP only (the LibBF branch is left to a later step); the
# `__WINDOWS__` exponent fix-up is left out too.
"""
    formatFloat(ld, locale, how, arg, f, out) -> Bool

Format the number `f` for `~e ~f ~g ~h` (and the capitals) into `out`: `how` is the directive character, `arg`
the number of digits (`FMT_DEFAULT`: 6, for `h` 3). Big integers and rationals are printed exactly, `h` and the
rest through the C `%e %f %g` (pl-fmt.c). The locale's decimal point and grouping are applied last.
"""
function formatFloat(
    ld::PL_local_data{T}, locale::Union{Nothing, PL_locale}, how::Int, arg::Int, f::number,
    out::Vector{UInt8}
)::Bool where {T}
    use_h = how == Int('h') || how == Int('H')
    if arg == FMT_DEFAULT
        arg = use_h ? 3 : 6
    elseif arg < 0 && !use_h
        a = PL_new_term_ref(ld)
        PL_put_integer(ld, a, arg)
        return PL_error(ld, ERR_DOMAIN, mk_sym(T, :not_less_than_zero), a)
    end

    use_h && !promoteToFloatNumber(ld, f) && return false

    t = f.type
    if t === V_MPZ
        if how == Int('f') || how == Int('F')
            _fmt_mpz_f!(out, f.mpz, arg)
        elseif how == Int('e') || how == Int('E')
            _fmt_mpz_e!(out, locale, how, arg, f.mpz)
            return true
        else                                                # g, G
            _fmt_mpz_g!(out, how, arg, f.mpz)
        end
    elseif t === V_MPQ
        if how == Int('f') || how == Int('F')
            _fmt_mpq_f!(out, f.mpq, arg)
        elseif how == Int('e') || how == Int('E')
            _fmt_mpq_e!(out, locale, how, arg, f.mpq)
            return true
        else                                                # g, G
            _fmt_mpq_g!(out, how, arg, f.mpq)
        end
    else
        if t === V_INTEGER
            promoteToFloatNumber(ld, f) || return false
        end
        if use_h
            append!(out, codeunits(format_float(f.f, arg, how == Int('H') ? 'E' : 'e')))
        else
            append!(out, codeunits(_fmt_c_printf_float(f.f, how, arg)))
        end
    end

    if locale !== nothing
        localizeDecimalPoint(locale, out) || return false
        groupDigits(locale, out) || return false
    end
    return true
end
