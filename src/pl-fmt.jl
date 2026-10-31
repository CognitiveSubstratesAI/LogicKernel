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
