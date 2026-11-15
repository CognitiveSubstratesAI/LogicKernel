# UPSTREAM: swipl-devel src/pl-term.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# THE TERMINAL (pl-term.c), since TTY1: `tty_size/2` (the window size of the terminal behind `user_input`),
# `tty_get_capability/3`, `tty_goto/2` and `tty_put/2` (the termcap interface of the terminal library).
#
# `tty_size/2` is the `TIOCGWINSZ` branch of upstream (pl-term.c:403-456): the `ioctl` of the descriptor
# `Sfileno(Suser_input)` (0 when that is below 0), answering `(Rows, Columns)` or `system_error` with the text of
# `errno`. It reads no field of the stream: the descriptor is all it needs.
#
# The three termcap predicates (pl-term.c:72-324) keep upstream's argument checks, error terms and order of
# checks; the calls into the terminal library (`tgetent`, `tgetnum`, `tgetflag`, `tgetstr`, `tgoto`, `tputs`,
# libtinfo) raise the refusal exception of the step TTY2, which owns linking that library (a `ccall` of the
# libtinfo functions, the `capabilities` table and `term_initialised` of `GD->terminal`).

# ── tty_size/2 ──────────────────────────────────────────────────────────────────────────────────

# ORIGINAL (TTY1): the value of `TIOCGWINSZ` of Linux's generic ioctl numbering (<asm-generic/ioctls.h>; the kernel runs
# on Linux, as `LIBC` assumes glibc). Upstream takes it from <sys/ioctl.h> (pl-term.c:418-428).
const TIOCGWINSZ = 0x00005413

# PORT: pl-term.c tty_size (the `ioctl` of its TIOCGWINSZ branch, pl-term.c:425-430)
# DIVERGES: the result is a tuple `(iorval, rows, cols, errno)` where upstream fills `struct winsize ws` and reads
# the global `errno` later: `ws` is four `UInt16` (`ws_row`, `ws_col`, `ws_xpixel`, `ws_ypixel`), zeroed first (upstream
# reads `ws_row` and `ws_col` also when the `ioctl` failed, and never uses them then); `ioctl` is variadic, called here
# with its third argument as a pointer, which Linux on x86-64 and aarch64 passes as the fixed-argument call does.
"The `ioctl(fd, TIOCGWINSZ)` result of descriptor `fd`: `(iorval, rows, cols, errno)` (`errno` read at once, pl-term.c)."
function _tty_winsize(fd::Int)::Tuple{Int, Int, Int, Int}
    ws = zeros(UInt16, 4)
    iorval = ccall((:ioctl, LIBC), Cint, (Cint, Culong, Ptr{UInt16}), fd, TIOCGWINSZ, ws)
    en = Int(Base.Libc.errno())
    return (Int(iorval), Int(ws[1]), Int(ws[2]), en)
end

# PORT: pl-term.c tty_size (the tail after the `ioctl`, pl-term.c:447-455)
"The answer of `tty_size/2` to an `ioctl` result: `system_error` for a failed one, else `(Rows, Columns)` unified (pl-term.c)."
function _tty_size_answer(
    ld::PL_local_data{T}, r::term_t, c::term_t, iorval::Int, rows::Int, cols::Int,
    errno::Int
)::Bool where {T}
    if iorval != 0
        return PL_error(ld, "tty_size", 2, MSG_ERRNO, ERR_SYSCALL, "ioctl", errno)
    end
    return PL_unify_integer(ld, r, rows) && PL_unify_integer(ld, c, cols)
end

# PORT: pl-term.c tty_size as pl_tty_size2_va
# (PRED_IMPL("tty_size", 2, tty_size, 0)) — pl-term.c:403-456
# DIVERGES (representation): `Sfileno(Suser_input)` is the descriptor of a standard stream only (`_std_fileno`: 0, 1,
# 2; FILENO1), -1 for every other stream, where upstream answers the descriptor a file stream bound to `user_input` has;
# -1 becomes 0 as upstream's `if ( fd < 0 ) fd = 0`.
"`tty_size(-Rows, -Columns)`: the size of the terminal behind `user_input`; `system_error` when it is no terminal (pl-term.c)."
function pl_tty_size2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    s = Suser_input(ld)
    fd = s isa IOSTREAM ? _std_fileno(ld, s) : -1
    if fd < 0
        fd = 0
    end
    iorval, rows, cols, en = _tty_winsize(fd)
    return _tty_size_answer(ld, A1, A2, iorval, rows, cols, en) ? FTRUE : FFALSE
end

# ── the termcap predicates ──────────────────────────────────────────────────────────────────────

# PORT: pl-term.c initTerm
# DIVERGES: the state `term_initialised` (`STAT_ERROR` after a failed first call, which makes every later call fail
# without an error) is a field of `GD->terminal` and is kept by TTY2; here every call looks at `TERM` again, so a call
# with `TERM` unset raises `existence_error(environment, 'TERM')` each time (upstream: the first call only). `TERM`
# of 100 bytes or more is as unset (upstream's 100 byte buffer, `Getenv` answers NULL).
"Initialise the terminal library from `TERM`: `false` with `existence_error(environment, 'TERM')` raised when it is unset (pl-term.c)."
function initTerm(ld::PL_local_data{T})::Bool where {T}
    term = getenv3("TERM")
    if term === nothing || ncodeunits(term) >= 100
        env = PL_new_term_ref(ld)
        PL_put_atom(ld, env, mk_sym(T, :TERM))
        PL_error(ld, "", 0, "", ERR_EXISTENCE, mk_sym(T, :environment), env)
        return false
    end
    throw(
        NotPortedError{T}(
            mk_sym(T, :tgetent), "tgetent() (the terminal database of libtinfo)", "TTY2"
        )
    )
end

# PORT: pl-term.c lookupEntry
# DIVERGES: no `capabilities` table (`GD->terminal`, TTY2): the lookup itself is `tgetnum`, `tgetflag` or `tgetstr`
# of libtinfo, reached when `initTerm` answers true; the answer is whether the capability has a value.
"Whether the terminal has capability `name` of `type` with a value; `false` when `initTerm` failed (pl-term.c)."
function lookupEntry(ld::PL_local_data{T}, name::T, type::T)::Bool where {T}
    initTerm(ld) || return false
    throw(
        NotPortedError{T}(
            name, "tgetnum(), tgetflag() and tgetstr() (the capabilities of libtinfo)", "TTY2"
        )
    )
end

# PORT: pl-term.c tty_get_capability as pl_tty_get_capability3_va
# (PRED_IMPL("tty_get_capability", 3, tty_get_capability, 0)) — pl-term.c:251-270
"`tty_get_capability(+Name, +Type, -Value)`: the termcap capability `Name` of `Type` (`number`, `bool`, `string`) (pl-term.c)."
function pl_tty_get_capability3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    A2 = PL__t0 + 1
    n = PL_get_atom_ex(ld, A1)
    n === nothing && return FFALSE
    t = PL_get_atom_ex(ld, A2)
    t === nothing && return FFALSE
    lookupEntry(ld, n, t)                    # (a capability with a value: unified with `A3` once TTY2 links libtinfo)
    return FFALSE
end

# PORT: pl-term.c tty_goto as pl_tty_goto2_va
# (PRED_IMPL("tty_goto", 2, tty_goto, 0)) — pl-term.c:280-306
# DIVERGES: `tgoto` and `tputs` (and `tputc`, the callback writing to `Suser_output`) are libtinfo's: TTY2.
"`tty_goto(+X, +Y)`: move the cursor to column `X`, row `Y` with the `cm` capability (pl-term.c)."
function pl_tty_goto2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    A2 = PL__t0 + 1
    ix = PL_get_integer_ex(ld, A1)
    ix === nothing && return FFALSE
    iy = PL_get_integer_ex(ld, A2)
    iy === nothing && return FFALSE
    if !lookupEntry(ld, mk_sym(T, :cm), mk_sym(T, :string))
        obj = PL_new_term_ref(ld)
        PL_put_atom(ld, obj, mk_sym(T, :cm))
        PL_error(
            ld, "tty_goto", 2, "", ERR_EXISTENCE, mk_sym(T, :terminal_capability), obj
        )
        return FFALSE
    end
    throw(
        NotPortedError{T}(
            mk_sym(T, :tgoto), "tgoto() and tputs() (the cursor motion string, libtinfo)",
            "TTY2"
        )
    )
end

# PORT: pl-term.c tty_put as pl_tty_put2_va
# (PRED_IMPL("tty_put", 2, pl_tty_put, 0)) — pl-term.c:309-324
# DIVERGES: `tputs` (padding and output through `tputc`) is libtinfo's: TTY2.
"`tty_put(+Atom, +Lines)`: write the terminal control string `Atom` with padding for `Lines` affected lines (pl-term.c)."
function pl_tty_put2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    A2 = PL__t0 + 1
    txt = PL_get_text(ld, A1, UInt32(CVT_ALL | CVT_EXCEPTION))
    txt === nothing && return FFALSE
    n = PL_get_integer_ex(ld, A2)
    n === nothing && return FFALSE
    throw(
        NotPortedError{T}(
            mk_sym(T, :tputs), "tputs() (output with padding, libtinfo)", "TTY2"
        )
    )
end

# PORT: pl-term.c BeginPredDefs as PL_predicates_from_term
# (pl-term.c:465-474: `tty_get_capability/3`, `tty_goto/2` and `tty_put/2` are guarded by `HAVE_TGETENT`, `tty_size/2` by
# `HAVE_TTY_SIZE_PRED`; both hold on the pin's Linux build.)
"pl-term.c's registration table (`BeginPredDefs(term)`): `tty_get_capability/3`, `tty_goto/2`, `tty_put/2`, `tty_size/2`."
const PL_predicates_from_term = (
    PL_extension("tty_get_capability", 3, pl_tty_get_capability3_va, PL_FA_VARARGS),
    PL_extension("tty_goto", 2, pl_tty_goto2_va, PL_FA_VARARGS),
    PL_extension("tty_put", 2, pl_tty_put2_va, PL_FA_VARARGS),
    PL_extension("tty_size", 2, pl_tty_size2_va, PL_FA_VARARGS)
)
