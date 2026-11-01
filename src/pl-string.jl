# UPSTREAM: swipl-devel src/pl-string.c @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  2012-2025, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# STRING PREDICATES (pl-string.c), since T2 (R2): the strings as text — atom_string/2, string_codes/2,
# string_chars/2, text_to_string/2, string_code/3, get_string_code/3, split_string/4, string_bytes/3,
# read_string/3,5 and open_string/2. Also here, from pl-prims.c, because the design names them in T2:
# string_length/2, string_concat/3 and sub_string/5 (with `sub_text`, which `sub_atom/5` shares: that
# predicate is pl-ext.c's table and NOT registered by T2). They sit on the T1 text layer
# (src/os/pl-text.jl: `PL_get_text`, `PL_unify_text`, `PL_cmp_text`) and on `concat` / `text_length`
# of src/pl-prims.jl. Registered by the table `PL_predicates_from_strings` (src/pl-ext.jl).

# PORT: pl-string.c unify_text
# DIVERGES: `PL_get_text` returns the text of an atom or a string as UTF-8, NOT canonical (see
# `PL_chars_t`), so the fallback compares the canonical forms: `txt` and `tt` are canonicalised first
# (upstream's are canonical already); `PL_exception(0)` is `ld.exception_term != 0`; no `PL_free_text`.
"""
Unify `t` with `txt` made a `type` (`PL_unify_text`); when that fails without an exception, `t` may hold a
text equal to `txt` in another type (a string for an atom, a code list for a string): then it is `txt`'s equal
(pl-string.c).
"""
function unify_text(
    ld::PL_local_data{T}, t::term_t, txt::PL_chars_t, type::Int
)::Bool where {T}
    PL_unify_text(ld, t, 0, txt, type) && return true
    if ld.exception_term == 0
        tt = PL_get_text(ld, t, CVT_ALL)
        if tt !== nothing
            PL_canonicalise_text(txt) == 1 || return false
            PL_canonicalise_text(tt) == 1 || return false
            return txt.encoding === tt.encoding &&
                   txt.length == tt.length &&
                   PL_cmp_text(txt, 0, tt, 0, tt.length) == 0
        end
    end
    return false
end

# PORT: pl-string.c atom_string as pl_atom_string2_va
# (PRED_IMPL("atom_string", 2, atom_string, 0))
"`atom_string/2` (pl-string.c): `A1` is the atom of the text of the string `A2`, or `A2` the string of the text of `A1`."
function pl_atom_string2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    a = PL__t0
    str = PL__t0 + 1

    t = PL_get_text(ld, str, CVT_ALL)
    if t !== nothing
        return unify_text(ld, a, t, PL_ATOM) ? FTRUE : FFALSE
    end
    t = PL_get_text(ld, a, CVT_ALL)
    if t !== nothing
        return unify_text(ld, str, t, PL_STRING) ? FTRUE : FFALSE
    elseif !PL_is_variable(ld, str)
        return PL_type_error(ld, "string", str) ? FTRUE : FFALSE
    elseif !PL_is_variable(ld, a)
        return PL_type_error(ld, "atom", a) ? FTRUE : FFALSE
    else
        return PL_error(ld, ERR_INSTANTIATION) ? FTRUE : FFALSE
    end
end

# PORT: pl-string.c string_x
# DIVERGES: `get_text_status` reads the three results of `PL_get_text` apart (`GT_TRUE`, `GT_FALSE`,
# `GT_ISVAR`, as T1's `x_chars`).
"""
The body of `string_codes/2` and `string_chars/2` (pl-string.c): `list` (made an `out_type`: `PL_CODE_LIST` or
`PL_CHAR_LIST`) is the text of `str`, or `str` the string of the text `list` holds.
"""
function string_x(
    ld::PL_local_data{T}, str::term_t, list::term_t, out_type::Int
)::Bool where {T}
    t = PL_get_text(ld, str, CVT_ALL | CVT_EXCEPTION | CVT_VARNOFAIL)
    st = get_text_status(t)
    if st == GT_TRUE
        return unify_text(ld, list, t::PL_chars_t, out_type)
    elseif st == GT_FALSE
        return false
    end                                                     # GT_ISVAR: can bind

    t = PL_get_text(ld, list, CVT_STRING | CVT_LIST | CVT_EXCEPTION)
    if t !== nothing
        return unify_text(ld, str, t, PL_STRING)
    end
    return false
end

# PORT: pl-string.c string_codes as pl_string_codes2_va
# (PRED_IMPL("string_codes", 2, string_codes, 0))
"`string_codes/2` (pl-string.c): a string and the list of its character codes."
function pl_string_codes2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return string_x(ld, PL__t0, PL__t0 + 1, PL_CODE_LIST) ? FTRUE : FFALSE
end

# PORT: pl-string.c string_chars as pl_string_chars2_va
# (PRED_IMPL("string_chars", 2, string_chars, 0))
"`string_chars/2` (pl-string.c): a string and the list of its characters."
function pl_string_chars2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return string_x(ld, PL__t0, PL__t0 + 1, PL_CHAR_LIST) ? FTRUE : FFALSE
end

# PORT: pl-string.c text_to_string as pl_text_to_string2_va
# (PRED_IMPL("text_to_string", 2, text_to_string, 0))
"`text_to_string/2` (pl-string.c): `A2` is the string of the text of `A1` (an atom, a code or character list, or a string)."
function pl_text_to_string2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    PL_is_string(ld, A1) && return PL_unify(ld, A1, A2) ? FTRUE : FFALSE

    t = PL_get_text(ld, A1, CVT_ATOM | CVT_LIST | CVT_EXCEPTION)
    if t !== nothing
        return unify_text(ld, A2, t, PL_STRING) ? FTRUE : FFALSE
    end
    return FFALSE
end

# ── string_length/2, string_concat/3, sub_string/5 (pl-prims.c 5496-5522, "Provisional String manipulation
# functions"), taken into T2 by the design ────────────────────────────────────────────────────────────

# PORT: pl-prims.c string_length as pl_string_length2_va
# (PRED_IMPL("string_length", 2, string_length, 0))
"`string_length/2` (pl-prims.c): the length of the text of `A1`, any atomic or a code or character list."
function pl_string_length2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return text_length(ld, PL__t0, PL__t0 + 1, CVT_ALL) ? FTRUE : FFALSE
end

# PORT: pl-prims.c string_concat as pl_string_concat3_va
# (PRED_IMPL("string_concat", 3, string_concat, PL_FA_NONDETERMINISTIC)) — T1's `concat` (src/pl-prims.jl)
# with the type `PL_STRING`.
"`string_concat/3` (pl-prims.c): `A3` is the string of the text of `A1` and `A2`; with `A3` alone, every split of it."
function pl_string_concat3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return concat(ld, PL__t0, PL__t0 + 1, PL__t0 + 2, true, PL__ctx, CVT_ATOMIC, PL_STRING)
end

# PORT: pl-prims.c enum sub_type
# DIVERGES: `Int` constants (upstream: an enum).
"`sub_text` state: sub given, but no position (pl-prims.c `SUB_SEARCH`)."
const SUB_SEARCH = 0
"`sub_text` state: before given, split tail (pl-prims.c `SUB_SPLIT_TAIL`)."
const SUB_SPLIT_TAIL = 1
"`sub_text` state: after given, split head (pl-prims.c `SUB_SPLIT_HEAD`)."
const SUB_SPLIT_HEAD = 2
"`sub_text` state: length given, move it (pl-prims.c `SUB_SPLIT_LEN`)."
const SUB_SPLIT_LEN = 3
"`sub_text` state: all free (pl-prims.c `SUB_ENUM`)."
const SUB_ENUM = 4

# PORT: pl-prims.c SIZE_NOT_SET
# DIVERGES: -1, where upstream's `size_t` is (size_t)-1.
"A size argument that is not given (pl-prims.c `SIZE_NOT_SET`)."
const SIZE_NOT_SET = -1

# ORIGINAL (T2): upstream's `sub_state` (type, n1, n2, n3) lives in a heap record behind `ForeignRedoPtr`; the
# kernel keeps such records in a pool of the local data (`foreign_state_pool`), which would need a field of
# pl-global.jl. This state is three small numbers, so it is packed into the `REDO_INT` context instead: the
# type in 3 bits, `n1` in 29 and `n2` in 29. `n3` (the haystack's length, or the given `before`, `length` or
# `after`) is read again from the arguments on a redo. FLAG for the audit: a text of 2^29 characters or more
# raises `representation_error(size_t)` here.
"The limit of a `sub_text` position: the 29 bits a packed state holds."
const SUB_STATE_LIMIT = 1 << 29
"A packed `sub_text` state: the type of enumeration `typ` and the numbers `n1`, `n2`."
@inline _sub_state(typ::Int, n1::Int, n2::Int)::Int = typ | (n1 << 3) | (n2 << 32)
"The type of enumeration a packed `sub_text` state holds."
@inline _sub_state_type(c::Int)::Int = c & 7
"The first number of a packed `sub_text` state."
@inline _sub_state_n1(c::Int)::Int = (c >> 3) & (SUB_STATE_LIMIT - 1)
"The second number of a packed `sub_text` state."
@inline _sub_state_n2(c::Int)::Int = (c >> 32) & (SUB_STATE_LIMIT - 1)

# PORT: pl-prims.c get_positive_integer_or_unbound
# DIVERGES: returns the value (`SIZE_NOT_SET` for an unbound `t`), or `nothing` where upstream returns false
# (the error raised by `PL_get_size_ex`).
"The non-negative integer `t` holds, `SIZE_NOT_SET` when it is unbound, `nothing` after an error (pl-prims.c)."
function get_positive_integer_or_unbound(
    ld::PL_local_data{T}, t::term_t
)::Union{Nothing, Int} where {T}
    PL_is_variable(ld, t) && return SIZE_NOT_SET
    return PL_get_size_ex(ld, t)
end

# PORT: pl-prims.c sub_text
# DIVERGES: the texts are `PL_get_text`'s (UTF-8 for an atom or a string), canonicalised after they are got; the state
# is packed into the `REDO_INT` context (see `_sub_state`) and rebuilt from the arguments on a redo (`n3` is one of
# `la`, `ls`, `b`, `l` or `a`); the foreign frame `fid` is closed on every exit, where upstream leaves it to the
# caller; `goto again` is the `while true`. The result of the last candidate of `SUB_SEARCH` is true whether or not
# its unifications succeeded, as upstream's `exit_succeed` after `++state->n1 + ls > la`.
"""
The body of `sub_atom/5` and `sub_string/5` (pl-prims.c): `sub` is the `len` characters of `atom` after `before`
characters and before `after`, of `type` `PL_ATOM` or `PL_STRING`; enumerates what is unbound.
"""
function sub_text(
    ld::PL_local_data{T}, atom::term_t, before::term_t, len::term_t, after::term_t,
    sub::term_t, h::control_t{T}, type::Int
)::foreign_t where {T}
    expected = mk_sym(T, type == PL_STRING ? :string : :atom)
    ctl = PL_foreign_control(h)
    ts = PL_init_text()
    b = SIZE_NOT_SET
    l = SIZE_NOT_SET
    a = SIZE_NOT_SET
    typ = SUB_ENUM
    n1 = 0
    n2 = 0

    ctl == FRG_CUTTED && return FTRUE
    t = PL_get_text(ld, atom, CVT_ATOMIC)
    if ctl == FRG_FIRST_CALL
        t === nothing && return PL_error(ld, ERR_TYPE, expected, atom) ? FTRUE : FFALSE
        ta = t::PL_chars_t
        PL_canonicalise_text_ex(ld, ta) || return FFALSE
        la = PL_text_length(ta)
        if la >= SUB_STATE_LIMIT
            return PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :size_t)) ? FTRUE : FFALSE
        end

        bb = get_positive_integer_or_unbound(ld, before)
        bb === nothing && return FFALSE
        ll = get_positive_integer_or_unbound(ld, len)
        ll === nothing && return FFALSE
        aa = get_positive_integer_or_unbound(ld, after)
        aa === nothing && return FFALSE
        b, l, a = bb, ll, aa

        tsub = PL_get_text(ld, sub, CVT_ATOMIC)
        if tsub === nothing
            PL_is_variable(ld, sub) ||
                return PL_error(ld, ERR_TYPE, expected, sub) ? FTRUE : FFALSE
        else
            ts = tsub
            PL_canonicalise_text_ex(ld, ts) || return FFALSE
        end

        if ts.encoding !== ENC_UNKNOWN                      # `sub' given
            ls = PL_text_length(ts)
            if l != SIZE_NOT_SET && ls != l                 # length conflict
                return FFALSE
            end
            if b != SIZE_NOT_SET                            # before given: test
                if PL_cmp_text(ta, b, ts, 0, ls) == CMP_EQUAL
                    rc = PL_unify_integer(ld, len, ls) && PL_unify_integer(ld, after, la - ls - b)
                    return rc ? FTRUE : FFALSE
                end
                return FFALSE
            end
            if a != SIZE_NOT_SET                            # after given: test
                if la >= a + ls
                    off = la - a - ls
                    if PL_cmp_text(ta, off, ts, 0, ls) == CMP_EQUAL
                        rc = PL_unify_integer(ld, len, ls) && PL_unify_integer(ld, before, off)
                        return rc ? FTRUE : FFALSE
                    end
                end
                return FFALSE
            end
            typ = SUB_SEARCH
            n1 = 0
        elseif b != SIZE_NOT_SET                            # before given
            b > la && return FFALSE

            if l != SIZE_NOT_SET                            # length given
                if b + l <= la                              # deterministic fit
                    if PL_unify_text_range(ld, sub, ta, b, l, type) &&
                       PL_unify_integer(ld, after, la - b - l)
                        return FTRUE
                    end
                end
                return FFALSE
            end
            if a != SIZE_NOT_SET                            # after given
                if la >= a + b
                    l2 = la - a - b
                    if PL_unify_text_range(ld, sub, ta, b, l2, type) &&
                       PL_unify_integer(ld, len, l2)
                        return FTRUE
                    end
                end
                return FFALSE
            end
            typ = SUB_SPLIT_TAIL
            n1 = 0                                          # length of the split
        elseif l != SIZE_NOT_SET                            # no before, length given
            l > la && return FFALSE

            if a != SIZE_NOT_SET                            # length and after
                if la >= a + l
                    b2 = la - a - l
                    if PL_unify_text_range(ld, sub, ta, b2, l, type) &&
                       PL_unify_integer(ld, before, b2)
                        return FTRUE
                    end
                end
                return FFALSE
            end
            typ = SUB_SPLIT_LEN
            n1 = 0                                          # before
        elseif a != SIZE_NOT_SET                            # only after given
            a > la && return FFALSE
            typ = SUB_SPLIT_HEAD
            n1 = 0                                          # before
        else
            typ = SUB_ENUM
            n1 = 0                                          # before
            n2 = 0                                          # length
        end
    elseif ctl == FRG_REDO
        c = PL_foreign_context(h)
        typ, n1, n2 = _sub_state_type(c), _sub_state_n1(c), _sub_state_n2(c)
        t === nothing && return FFALSE
        ta = t
        PL_canonicalise_text_ex(ld, ta) || return FFALSE
        la = PL_text_length(ta)
        bb = get_positive_integer_or_unbound(ld, before)
        ll = get_positive_integer_or_unbound(ld, len)
        aa = get_positive_integer_or_unbound(ld, after)
        (bb === nothing || ll === nothing || aa === nothing) && return FFALSE
        b, l, a = bb, ll, aa
        if typ == SUB_SEARCH
            tsub = PL_get_text(ld, sub, CVT_ATOMIC)
            tsub === nothing && return FFALSE
            ts = tsub
            PL_canonicalise_text_ex(ld, ts) || return FFALSE
        end
    else
        error("sub_text: unknown control $ctl")             # assert(0)
    end

    ta = t::PL_chars_t
    la = PL_text_length(ta)
    ls = PL_text_length(ts)
    fid = PL_open_foreign_frame(ld)
    while true                                              # again:
        match = false
        outcome = 0                                         # 0: next, 1: exit_succeed, 2: exit_fail
        if typ == SUB_SEARCH
            outcome = 2
            while n1 + ls <= la
                if PL_cmp_text(ta, n1, ts, 0, ls) == 0
                    match = PL_unify_integer(ld, before, n1) &&
                            PL_unify_integer(ld, len, ls) &&
                            PL_unify_integer(ld, after, la - ls - n1)
                    n1 += 1
                    outcome = n1 + ls > la ? 1 : 0
                    break
                end
                n1 += 1
            end
        elseif typ == SUB_SPLIT_TAIL                        # before given, rest unbound
            l = n1
            n1 += 1
            match = PL_unify_text_range(ld, sub, ta, b, l, type) &&
                    PL_unify_integer(ld, len, l) &&
                    PL_unify_integer(ld, after, la - b - l)
            outcome = b + l < la ? 0 : (match ? 1 : 2)      # out:
        elseif typ == SUB_SPLIT_LEN
            b = n1
            n1 += 1
            match = PL_unify_text_range(ld, sub, ta, b, l, type) &&
                    PL_unify_integer(ld, before, b) &&
                    PL_unify_integer(ld, after, la - b - l)
            outcome = b + l < la ? 0 : (match ? 1 : 2)      # out:
        elseif typ == SUB_SPLIT_HEAD
            b = n1
            n1 += 1
            l = la - a - b
            match = PL_unify_text_range(ld, sub, ta, b, l, type) &&
                    PL_unify_integer(ld, before, b) &&
                    PL_unify_integer(ld, len, l)
            outcome = l > 0 ? 0 : (match ? 1 : 2)
        else                                                # SUB_ENUM
            b = n1
            l = n2
            n2 += 1
            a = la - b - l
            match = PL_unify_text_range(ld, sub, ta, b, l, type) &&
                    PL_unify_integer(ld, before, b) &&
                    PL_unify_integer(ld, len, l) &&
                    PL_unify_integer(ld, after, a)
            outcome = 0
            if a == 0
                if b == la
                    outcome = match ? 1 : 2
                else
                    n2 = 0
                    n1 += 1
                end
            end
        end

        if outcome == 1                                     # exit_succeed
            PL_close_foreign_frame(ld, fid)
            return FTRUE
        elseif outcome == 2                                 # exit_fail
            PL_close_foreign_frame(ld, fid)
            return FFALSE
        end
        if match                                            # next:
            PL_close_foreign_frame(ld, fid)
            return PL_retry(_sub_state(typ, n1, n2))        # ForeignRedoPtr(state)
        elseif ld.exception_term == 0
            PL_rewind_foreign_frame(ld, fid)
        else
            PL_close_foreign_frame(ld, fid)
            return FFALSE
        end
    end
end

# PORT: pl-prims.c sub_string as pl_sub_string5_va
# (PRED_IMPL("sub_string", 5, sub_string, PL_FA_NONDETERMINISTIC))
"`sub_string/5` (pl-prims.c): `A5` is the sub-string of `A1` of length `A3`, after `A2` characters and before `A4`."
function pl_sub_string5_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return sub_text(
        ld, PL__t0, PL__t0 + 1, PL__t0 + 2, PL__t0 + 3, PL__t0 + 4, PL__ctx, PL_STRING
    )
end

# ── string_code/3, get_string_code/3 (pl-string.c 255-388) ───────────────────────────────────────────

# PORT: pl-error.c ERR_RANGE (PL_error)
# DIVERGES: the code `ERR_RANGE` is not in the kernel's `PL_error_code` enum (src/pl-error.jl); the error is built
# here from the open and close halves of `PL_error`: `error(domain_error(range(Low, High), Arg), context(Pred, _))`.
# A new enum member (and its `_enum_hash` manifest entry) is left to the audit.
"Raise `error(domain_error(range(low, high), arg), …)` (pl-error.c `ERR_RANGE`); false."
function PL_error_range(
    ld::PL_local_data{T}, low::term_t, high::term_t, arg::term_t
)::Bool where {T}
    h = _PL_error_open(ld)
    h === nothing && return false
    caller, fid, except, formal, swi = h
    r = new_term_ref(ld)
    PL_cons_functor(ld, r, _err_functor(ld, :range, 2), low, high)
    PL_cons_functor(ld, formal, _err_functor(ld, :domain_error, 2), r, arg)
    return _PL_error_close!(ld, caller, fid, except, formal, swi)
end

# PORT: pl-privitf.c PL_get_char
# DIVERGES: returns the code, or `nothing` where upstream returns false; upstream raises `type_error(character,
# C)` at its end, so this is also `PL_get_char_ex` (pl-error.c: the same error). NOT PORTED, as no caller passes
# it: `eof` (the integer -1 and the atom `end_of_file`).
"The character code term reference `c` holds — a code, a one-character atom, string or list; `nothing` after the error (pl-privitf.c)."
function PL_get_char(ld::PL_local_data{T}, c::term_t)::Union{Nothing, Int} where {T}
    chr = PL_get_integer(ld, c)
    if chr !== nothing
        VALID_CODE_POINT(chr) && return chr
        PL_type_error(ld, "character_code", c)
        return nothing
    end
    name = PL_get_atom(ld, c)
    if name !== nothing
        ch = charCode(name)
        ch != -1 && return ch
    else
        text = PL_get_text(ld, c, CVT_ATOM | CVT_STRING | CVT_LIST)
        if text !== nothing && PL_canonicalise_text(text) == 1 && PL_text_length(text) == 1
            return text_get_char(text, 0)
        end
    end
    PL_error(ld, ERR_TYPE, mk_sym(T, :character), c)
    return nothing
end

# PORT: pl-error.c PL_get_int64_ex
# DIVERGES: returns the value, or `nothing` with the error raised; `representation_error(int64_t)` as swipl 10.1.19
# raises it (the kernel's `PL_get_long_ex` names `long`).
"The 64-bit integer term reference `t` holds, or `nothing` after raising `representation_error(int64_t)` or `type_error(integer, T)` (pl-error.c)."
function PL_get_int64_ex(ld::PL_local_data{T}, t::term_t)::Union{Nothing, Int} where {T}
    i = PL_get_long(ld, t)
    i === nothing || return i
    if PL_is_integer(ld, t)
        PL_error(ld, ERR_REPRESENTATION, mk_sym(T, :int64_t))
        return nothing
    end
    PL_error(ld, ERR_TYPE, mk_sym(T, :integer), t)
    return nothing
end

# PORT: pl-string.c text_code_at
# DIVERGES: the code, or `nothing` where upstream returns false; `PL_text_unit_offset` is `PL_seek_text` (a unit is a
# code point) and `text_next_code` is `text_get_char`; `t` is canonical.
"The code of the character `index` (0-based) of the canonical text `t`, or `nothing` when `index` is beyond it (pl-string.c)."
function text_code_at(t::PL_chars_t, index::Int)::Union{Nothing, Int}
    u = PL_seek_text(t, index)
    (u == -1 || u >= t.length) && return nothing
    return text_get_char(t, u)
end

# PORT: pl-string.c string_code as pl_string_code3_va
# (PRED_IMPL("string_code", 3, string_code, PL_FA_NONDETERMINISTIC)) — `ForeignRedoInt(idx)` is `PL_retry(idx)`.
"`string_code/3` (pl-string.c): the character `A1` (counted from 1) of the text `A2` has code `A3`; enumerates the indices."
function pl_string_code3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    ctl = PL_foreign_control(PL__ctx)
    idx = 0
    tchar = -1

    if ctl == FRG_FIRST_CALL
        t = PL_get_text(ld, A2, CVT_ATOM | CVT_STRING | CVT_LIST | CVT_EXCEPTION)
        t === nothing && return FFALSE
        PL_canonicalise_text_ex(ld, t) || return FFALSE
        if !PL_is_variable(ld, A1)
            i = PL_get_size_ex(ld, A1)
            i === nothing && return FFALSE
            c = i == 0 ? nothing : text_code_at(t, i - 1)
            c === nothing && return FFALSE
            return PL_unify_integer(ld, A3, c) ? FTRUE : FFALSE
        else
            if !PL_is_variable(ld, A3)
                tc = PL_get_char(ld, A3)             # PL_get_char_ex
                tc === nothing && return FFALSE
                tchar = tc
            elseif t.length > 0
                tchar = -1
            else
                return FFALSE
            end
            idx = 0
        end
    elseif ctl == FRG_REDO
        idx = PL_foreign_context(PL__ctx)
        t = PL_get_text(ld, A2, CVT_ALL)
        t === nothing && return FFALSE
        PL_canonicalise_text_ex(ld, t) || return FFALSE
        if PL_is_variable(ld, A3)
            tchar = -1
        else
            tc = PL_get_char(ld, A3)
            tc === nothing && return FFALSE
            tchar = tc
        end
    else
        return FTRUE
    end

    # gen:
    u = PL_seek_text(t, idx)
    u == -1 && return FFALSE
    if tchar == -1
        if u < t.length &&
           PL_unify_integer(ld, A1, idx + 1) &&
           PL_unify_integer(ld, A3, text_get_char(t, u))
            u += 1
            return u < t.length ? PL_retry(idx + 1) : FTRUE
        end
        return FFALSE
    end

    while u < t.length
        c = text_get_char(t, u)
        u += 1
        if c == tchar
            if PL_unify_integer(ld, A1, idx + 1)
                idx += 1
                while u < t.length
                    c = text_get_char(t, u)
                    u += 1
                    c == tchar && return PL_retry(idx)
                    idx += 1
                end
                return FTRUE
            end
            return FFALSE
        end
        idx += 1
    end

    return FFALSE
end

# PORT: pl-string.c get_string_code as pl_get_string_code3_va
# (PRED_IMPL("get_string_code", 3, get_string_code, 0))
"`get_string_code/3` (pl-string.c): the character `A1` (counted from 1) of the text `A2` has code `A3`; out of range is `domain_error(range(1, Length), A1)`."
function pl_get_string_code3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2

    t = PL_get_text(ld, A2, CVT_ALL | CVT_EXCEPTION)
    t === nothing && return FFALSE
    i = PL_get_int64_ex(ld, A1)
    i === nothing && return FFALSE
    PL_canonicalise_text_ex(ld, t) || return FFALSE

    c = i < 1 ? nothing : text_code_at(t, i - 1)
    if c === nothing
        av = PL_new_term_refs(ld, 2)
        if av != 0
            PL_put_int64(ld, av, 1)
            PL_put_int64(ld, av + 1, PL_text_length(t))
            return PL_error_range(ld, av, av + 1, A1) ? FTRUE : FFALSE
        end
        return FFALSE
    end
    return PL_unify_integer(ld, A3, c) ? FTRUE : FFALSE
end

# ── split_string/4 (pl-string.c 386-472) ────────────────────────────────────────────────────────────

# PORT: pl-text.h text_chr
# DIVERGES: the offset is 0-based, -1 for (size_t)-1. The C string semantics of upstream's `strchr`/`wcschr` are
# kept: the search ends at the first NUL, and a NUL (`chr == 0`) is found there, or at the end of the text. So a NUL
# in the text `split_string/4` splits is a separator and a padding character, as swipl's.
"The offset of the first `chr` in the canonical text `t`, or -1 (pl-text.h; C string semantics)."
function text_chr(t::PL_chars_t, chr::Int)::Int
    @assert t.canonical "text_chr: a text that is not canonical"
    for i in 0:(t.length - 1)
        c = text_get_char(t, i)
        c == chr && return i
        c == 0 && return -1
    end
    return chr == 0 ? t.length : -1
end

# PORT: pl-string.c split_string as pl_split_string4_va
# (PRED_IMPL("split_string", 4, split_string, 0))
# DIVERGES: the three texts are canonicalised after `PL_get_text`; the offsets are 0-based code point indices
# (`text_next_code` is `text_get_char`, `text_prev_code` the code before the offset); `goto no_skip_padding` is
# the flag `skip`; `PL_unify_text_units` is T1's `unify_text_between`; `PL_unify_chars(head, PL_STRING, 0, "")`
# is the empty string made with `PL_unify_text`.
"""
`split_string/4` (pl-string.c): `A4` is the list of the strings `A1` splits into at the characters of `A2`, each
with the characters of `A3` stripped from both ends; an empty `A2` only strips.
"""
function pl_split_string4_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3, A4 = PL__t0, PL__t0 + 1, PL__t0 + 2, PL__t0 + 3
    flags = CVT_ATOM | CVT_STRING | CVT_LIST | CVT_EXCEPTION

    input = PL_get_text(ld, A1, flags)
    input === nothing && return FFALSE
    sep = PL_get_text(ld, A2, flags)
    sep === nothing && return FFALSE
    pad = PL_get_text(ld, A3, flags)
    pad === nothing && return FFALSE
    PL_canonicalise_text_ex(ld, input) || return FFALSE
    PL_canonicalise_text_ex(ld, sep) || return FFALSE
    PL_canonicalise_text_ex(ld, pad) || return FFALSE

    tail = PL_copy_term_ref(ld, A4)
    head = PL_new_term_ref(ld)
    sep_at = -1

    en = input.length                                       # back skip padding at end
    while en > 0
        text_chr(pad, text_get_char(input, en - 1)) == -1 && break
        en -= 1
    end

    i = 0
    skip = true
    while true
        if skip                                             # skip padding
            while i < en
                text_chr(pad, text_get_char(input, i)) == -1 && break
                i += 1
            end

            if i == en
                empty = PL_chars_t(UInt8[], 0, ENC_ISO_LATIN_1, true)
                if !PL_unify_list_ex(ld, tail, head, tail) ||
                   !PL_unify_text(ld, head, 0, empty, PL_STRING)
                    return FFALSE
                end
                break
            end
        end
        skip = true                                         # no_skip_padding:

        last = i                                            # find sep
        while i < en
            text_chr(sep, text_get_char(input, i)) != -1 && break
            i += 1
        end
        sep_at = i                                          # back skip padding
        while i > last
            text_chr(pad, text_get_char(input, i - 1)) == -1 && break
            i -= 1
        end

        if !PL_unify_list_ex(ld, tail, head, tail) ||
           !unify_text_between(ld, head, input, last, i, PL_STRING)
            return FFALSE
        end

        sep_at == en && break                               # no separator found

        i = sep_at
        sep_chr = text_get_char(input, i)
        i += 1
        next_chr = i < input.length ? text_get_char(input, i) : 0

        if text_chr(pad, sep_chr) == -1 && text_chr(sep, next_chr) != -1
            skip = false                                    # goto no_skip_padding
        end
    end

    return PL_unify_nil(ld, tail) ? FTRUE : FFALSE
end

# ── string_bytes/3 (pl-string.c 194-262) ────────────────────────────────────────────────────────────

# PORT: pl-string.c unit_length
# DIVERGES: `sizeof(wchar_t)` is 4, as the kernel's `ENC_WCHAR` text (src/os/pl-text.jl).
"The size in bytes of one unit of text in `enc`, the `length` of a text counting units (pl-string.c)."
unit_length(enc::IOENC)::Int = enc === ENC_WCHAR ? 4 : 1

# PORT: pl-text.h ERR_TEXT_ILLEGAL_UTF16, ERR_TEXT_INCOMPLETE_MULTIBYTE_SEQUENCE
# DIVERGES: `PL_canonicalise_text` of src/os/pl-text.jl gives only `ERR_TEXT_INVALID_CODE_POINT`; these two come
# from the UTF-16 decode below (`utf16_to_text`).
"`utf16_to_text`'s error: a lead surrogate without its trail (pl-text.h)."
const ERR_TEXT_ILLEGAL_UTF16 = -2
"`utf16_to_text`'s error: an odd number of bytes in a UTF-16 text (pl-text.h)."
const ERR_TEXT_INCOMPLETE_MULTIBYTE_SEQUENCE = -4

# PORT: pl-utf8.h IS_UTF16_LEAD, IS_UTF16_TRAIL, utf16_decode, utf16_encode
"True for a UTF-16 lead surrogate (pl-utf8.h)."
IS_UTF16_LEAD(c::Integer)::Bool = c >= 0xD800 && c <= 0xDBFF
"True for a UTF-16 trail surrogate (pl-utf8.h)."
IS_UTF16_TRAIL(c::Integer)::Bool = c >= 0xDC00 && c <= 0xDFFF
"The code point of a UTF-16 surrogate pair (pl-utf8.h)."
utf16_decode(lead::Integer, trail::Integer)::Int =
    ((Int(lead) - 0xD800) << 10) + (Int(trail) - 0xDC00) + 0x10000
"The lead and the trail surrogate of the code point `c` above 0xffff (pl-utf8.h)."
function utf16_encode(c::Integer)::Tuple{Int, Int}
    c = Int(c) - 0x10000
    return ((c >> 10) + 0xD800, (c & 0x3FF) + 0xDC00)
end

# PORT: pl-text.c PL_canonicalise_text (the ENC_UTF16LE and ENC_UTF16BE case)
# DIVERGES: src/os/pl-text.jl's `PL_canonicalise_text` refuses the two encodings by name, so the decode is here
# and returns the text, or the error code; the byte order is read explicitly where upstream flips the bytes
# (`flip_shorts`) to the native order. The wide branch is upstream's as it stands (pl-text.c, `if ( wide )`): a
# lead surrogate is replaced by the pair's code point and the loop steps ONE unit, so the trail is copied as a
# character too, and `length` is the number of units. The result is not canonical: the trail is then refused
# by `PL_canonicalise_text` (`ERR_TEXT_INVALID_CODE_POINT`), the answer of swipl 10.1.19 for every surrogate pair.
"""
    utf16_to_text(text) -> PL_chars_t or ERR_TEXT_*

The text a UTF-16 `text` (`length` in bytes) holds: ISO Latin-1 when every unit is at most 0xff, else
`ENC_WCHAR`; an error code for an odd length or a lead surrogate without a trail (pl-text.c).
"""
function utf16_to_text(text::PL_chars_t)::Union{PL_chars_t, Int}
    text.length % 2 != 0 && return ERR_TEXT_INCOMPLETE_MULTIBYTE_SEQUENCE
    len = text.length ÷ 2
    be = text.encoding === ENC_UTF16BE
    w = Vector{Int}(undef, len)
    for i in 1:len
        b0 = Int(text.text[2i - 1])
        b1 = Int(text.text[2i])
        w[i] = be ? (b0 << 8) | b1 : (b1 << 8) | b0
    end

    wide = false
    i = 1
    while i <= len
        w[i] > 0xff && (wide = true)
        if IS_UTF16_LEAD(w[i])
            if i + 1 <= len && IS_UTF16_TRAIL(w[i + 1])
                i += 1
            else
                return ERR_TEXT_ILLEGAL_UTF16
            end
        end
        i += 1
    end

    if wide
        to = UInt32[]
        i = 1
        while i <= len
            if IS_UTF16_LEAD(w[i])
                push!(to, utf16_decode(w[i], w[i + 1]))
            else
                push!(to, w[i])
            end
            i += 1                                          # upstream: `w++` in both branches
        end
        return PL_chars_t(Vector{UInt8}(reinterpret(UInt8, to)), len, ENC_WCHAR, false)
    else
        return PL_chars_t(UInt8[c for c in w], len, ENC_ISO_LATIN_1, false)
    end
end

# PORT: pl-error.c PL_syntax_error (the form without a stream)
# DIVERGES: only `in == NULL`: the location is left unbound (no stream table).
"Raise `error(syntax_error(Msg), _)` (pl-error.c `PL_syntax_error(msg, NULL)`); false."
function PL_syntax_error(ld::PL_local_data{T}, msg::String, ::Nothing)::Bool where {T}
    ex = PL_new_term_ref(ld)
    formal = PL_new_term_ref(ld)
    loc = PL_new_term_ref(ld)
    PL_cons_functor(
        ld, formal, _err_functor(ld, :syntax_error, 1), _err_atom(ld, mk_sym(T, Symbol(msg)))
    )
    PL_cons_functor(ld, ex, _err_functor(ld, :error, 2), formal, loc)
    return PL_raise_exception(ld, ex)
end

# PORT: pl-text.c text_error (the two UTF-16 codes)
"Raise the error for the code `rc` of `utf16_to_text` or of `PL_canonicalise_text`; false (pl-text.c)."
function string_bytes_text_error(ld::PL_local_data{T}, rc::Int)::Bool where {T}
    rc == ERR_TEXT_ILLEGAL_UTF16 && return PL_syntax_error(ld, "illegal_utf16_sequence", nothing)
    rc == ERR_TEXT_INCOMPLETE_MULTIBYTE_SEQUENCE &&
        return PL_syntax_error(ld, "incomplete_multibyte_sequence", nothing)
    return text_error(ld, rc)
end

# ORIGINAL (T2): upstream's `PL_encoding_to_atom` (NOT PORTED in src/os/pl-file.jl) as the first name of
# `encoding_names` that has `enc`.
"The name of the encoding `enc` (pl-file.c `PL_encoding_to_atom`'s atom text)."
function encoding_name(enc::IOENC)::String
    for (n, e) in encoding_names
        e === enc && return String(n)
    end
    error("encoding_name: no name for $enc")
end

# PORT: pl-text.c text_representation_error
"Raise `representation_error(encoding)` with the message `cannot represent text using encoding Name`; false (pl-text.c)."
function text_representation_error(ld::PL_local_data{T}, enc::IOENC)::Bool where {T}
    msg = "cannot represent text using encoding " * encoding_name(enc)
    return PL_error(ld, "", 0, msg, ERR_REPRESENTATION, mk_sym(T, :encoding))
end

# PORT: pl-text.c PL_text_recode
# DIVERGES: the encodings `string_bytes/3` reaches: the target is `ENC_UTF8`, `ENC_ISO_LATIN_1`, `ENC_OCTET`,
# `ENC_ASCII`, `ENC_UTF16LE` or `ENC_UTF16BE` and `text` is canonical (the caller canonicalises it; upstream's
# `PL_get_text` gives canonical texts, the kernel's does not, see `PL_chars_t`). The bytes go into `text.text`
# (a Julia vector: no buffers), the `length` is in bytes for UTF-8 and UTF-16, in characters for the others.
# NOT PORTED: the `ENC_ANSI` source and target (the locale; `string_bytes/3` refuses it by name first).
"Recode the canonical `text` to `encoding` in place; false after the error (pl-text.c)."
function PL_text_recode(ld::PL_local_data{T}, text::PL_chars_t, encoding::IOENC)::Bool where {T}
    text.encoding === encoding && return true
    if encoding === ENC_UTF8
        if text.encoding === ENC_ISO_LATIN_1
            if !any(c -> c & 0x80 != 0, text.text)           # ASCII; nothing to do
                text.encoding = ENC_UTF8
                text.canonical = false
                return true
            end
        end
        b = UInt8[]
        for c in _text_code_points(text)
            utf8_put_char(b, c)
        end
        text.text = b
        text.length = length(b)
        text.encoding = ENC_UTF8
        text.canonical = false
        return true
    elseif encoding === ENC_ISO_LATIN_1 || encoding === ENC_OCTET || encoding === ENC_ASCII
        @assert text.canonical "PL_text_recode: a text that is not canonical"
        text.encoding === ENC_WCHAR && return text_representation_error(ld, encoding)
        if encoding === ENC_ASCII
            for c in text.text
                c >= 128 && return text_representation_error(ld, encoding)
            end
        end
        text.canonical = false
        text.encoding = encoding
        return true
    elseif encoding === ENC_UTF16LE || encoding === ENC_UTF16BE
        @assert text.canonical "PL_text_recode: a text that is not canonical"
        b = UInt8[]
        for c in _text_code_points(text)
            units = c > 0xffff ? utf16_encode(c) : (c,)
            for u in units                                  # addUTF16Buffer_unit
                if encoding === ENC_UTF16LE
                    push!(b, UInt8(u & 0xff), UInt8(u >> 8))
                else
                    push!(b, UInt8(u >> 8), UInt8(u & 0xff))
                end
            end
        end
        text.text = b
        text.length = length(b)
        text.encoding = encoding
        text.canonical = false
        return true
    end
    throw(
        NotPortedError{Nothing}(
            nothing, "PL_text_recode to $encoding", "the locale (ENC_ANSI) is refused by name"
        )
    )
end

# PORT: pl-string.c string_bytes as pl_string_bytes3_va
# (PRED_IMPL("string_bytes", 3, string_bytes, 0))
# DIVERGES: `PL_get_nchars(A2, …, CVT_LIST|REP_ISO_LATIN_1|CVT_EXCEPTION)` is `PL_get_text` plus the refusal
# of a wide text, `representation_error(encoding)` for ISO Latin-1 as upstream's `PL_mb_text`; the byte list is
# a canonical ISO Latin-1 text. `PL_unify_chars(A2, PL_CODE_LIST|REP_ISO_LATIN_1, …)` is `PL_unify_text` of
# that text. NOT PORTED: the encoding `text` (`ENC_ANSI`, the locale) is refused by name, `NotPortedError`.
# Decoding with `ascii` ends in `PL_canonicalise_text` of `ENC_ASCII`, refused by name there (swipl 10.1.19
# fails an assertion at that line).
"""
`string_bytes/3` (pl-string.c): `A2` is the list of bytes of the text `A1` in the encoding `A3`, or `A1` the
string the bytes `A2` hold in that encoding.
"""
function pl_string_bytes3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2

    ename = PL_get_atom_ex(ld, A3)
    ename === nothing && return FFALSE
    enc = PL_atom_to_encoding(ename)
    if enc === ENC_UNKNOWN || enc === ENC_WCHAR
        return PL_domain_error(ld, "encoding", A3) ? FTRUE : FFALSE
    end
    enc === ENC_ANSI && throw(
        NotPortedError{T}(
            ename, "string_bytes/3 with the encoding text", "ENC_ANSI is the locale"
        )
    )

    t = PL_get_text(
        ld, A1, CVT_ATOM | CVT_STRING | CVT_LIST | CVT_EXCEPTION | CVT_VARNOFAIL
    )
    st = get_text_status(t)
    if st == GT_TRUE
        txt = t::PL_chars_t
        PL_canonicalise_text_ex(ld, txt) || return FFALSE
        PL_text_recode(ld, txt, enc) || return FFALSE
        n = txt.length * unit_length(txt.encoding)
        out = PL_chars_t(txt.text[1:n], n, ENC_ISO_LATIN_1, true)
        return PL_unify_text(ld, A2, 0, out, PL_CODE_LIST) ? FTRUE : FFALSE
    elseif st == GT_FALSE
        return FFALSE
    end                                                     # GT_ISVAR: can unify

    bytes = PL_get_text(ld, A2, CVT_LIST | CVT_EXCEPTION)
    bytes === nothing && return FFALSE
    PL_canonicalise_text_ex(ld, bytes) || return FFALSE
    bytes.encoding === ENC_WCHAR &&
        return text_representation_error(ld, ENC_ISO_LATIN_1) ? FTRUE : FFALSE
    len = bytes.length
    if len % unit_length(enc) != 0
        return PL_syntax_error(ld, "incomplete_multibyte_sequence", nothing) ? FTRUE :
               FFALSE
    end

    txt = PL_chars_t(bytes.text[1:len], len ÷ unit_length(enc), enc, false)
    if enc === ENC_UTF16LE || enc === ENC_UTF16BE
        r = utf16_to_text(txt)
        r isa Int && return string_bytes_text_error(ld, r) ? FTRUE : FFALSE
        txt = r
    end
    return PL_unify_text(ld, A1, 0, txt, PL_STRING) ? FTRUE : FFALSE
end

# ── read_string/5, read_string/3 and open_string/2 (pl-string.c 478-620) ───────────────────────────────

# PORT: pl-file.c PL_release_stream
# DIVERGES: no locks (`releaseStream`, as `streamStatus`, src/os/pl-file.jl): the verdict is the stream's error
# state, raised if it holds one.
"Whether the stream `s` is free of errors after the predicate's use; an error recorded on it is raised (pl-file.c)."
PL_release_stream(ld::PL_local_data, s::IOSTREAM)::Bool = streamStatus(ld, s)

# PORT: pl-string.c backSkipPadding
# DIVERGES: the buffer is a vector, `len` its used bytes; the result is the new used length (upstream: the end
# pointer). `backSkipUTF8` is T1-era pl-read.jl's, 1-based; `pad` is canonical (the caller canonicalises it).
"The length of the UTF-8 bytes `in[1:len]` without the characters of `pad` at their end (pl-string.c)."
function backSkipPadding(in::Vector{UInt8}, len::Int, pad::PL_chars_t)::Int
    stop = len + 1
    while stop > 1
        e, chr = backSkipUTF8(in, 1, stop)
        text_chr(pad, chr) == -1 && break
        stop = e
    end
    return stop - 1
end

# PORT: pl-string.c read_string as pl_read_string5_va
# (PRED_IMPL("read_string", 5, read_string, 0))
# DIVERGES: the separator and the padding texts are canonicalised after `PL_get_text` (`text_chr` needs canonical
# texts; upstream's are); `PL_release_stream` is `streamStatus` (no locks); the buffer is a byte vector
# (`addUTF8Buffer`), the string made from it with `PL_unify_text` (`PL_unify_chars(…, PL_STRING|REP_UTF8, …)`).
# `text_chr` keeps the C string semantics (a NUL read is a separator and a padding character).
"""
`read_string(+Stream, +Delimiters, +Padding, -Delimiter, -String)` (pl-string.c): skip the padding, read up to a
delimiter or the end of the file, strip the padding from the end; `Delimiter` is the code read, -1 at the end.
"""
function pl_read_string5_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3, A4, A5 = PL__t0, PL__t0 + 1, PL__t0 + 2, PL__t0 + 3, PL__t0 + 4
    flags = CVT_ATOM | CVT_STRING | CVT_LIST | CVT_EXCEPTION
    rc = false

    s = getTextInputStream(ld, A1)
    s === nothing && return FFALSE
    sep = PL_get_text(ld, A2, flags)
    pad = sep === nothing ? nothing : PL_get_text(ld, A3, flags)
    if sep !== nothing && pad !== nothing &&
       PL_canonicalise_text_ex(ld, sep) && PL_canonicalise_text_ex(ld, pad)
        tmpbuf = UInt8[]
        chr = Sgetcode(s)
        while chr != EOF && text_chr(pad, chr) != -1
            chr = Sgetcode(s)
        end

        failed = false
        while true
            if chr == EOF && Sferror(s) != 0
                failed = true                               # goto out
                break
            end
            (chr == EOF || text_chr(sep, chr) != -1) && break
            addUTF8Buffer(tmpbuf, chr)
            chr = Sgetcode(s)
        end

        if !failed
            n = backSkipPadding(tmpbuf, length(tmpbuf), pad)
            str = PL_chars_t(tmpbuf[1:n], length(String(tmpbuf[1:n])), ENC_UTF8, false)
            rc = PL_unify_text(ld, A5, 0, str, PL_STRING) && PL_unify_integer(ld, A4, chr)
        end
    end

    released = PL_release_stream(ld, s)                     # out:
    return (rc && released) ? FTRUE : FFALSE
end

# PORT: pl-string.c read_string as pl_read_string3_va
# (PRED_IMPL("read_string", 3, read_string, 0))
# DIVERGES: as `read_string/5` for the stream release and the string; `len` unset (`(size_t)-1`) is `typemax(Int)`.
"""
`read_string(+Stream, ?Length, -String)` (pl-string.c): read `Length` characters, or up to the end of the file if
`Length` is unbound, which is then unified with the count.
"""
function pl_read_string3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    len = typemax(Int)                                      # (size_t)-1
    rc = false

    s = getTextInputStream(ld, A1)
    s === nothing && return FFALSE
    vlen = PL_is_variable(ld, A2)
    ok = true
    if !vlen
        l = PL_get_size_ex(ld, A2)
        l === nothing ? (ok = false) : (len = l)
    end
    if ok
        tmpbuf = UInt8[]
        count = 0
        failed = false
        while count < len
            chr = Sgetcode(s)
            if chr == EOF
                Sferror(s) != 0 && (failed = true)          # goto out
                break
            end
            addUTF8Buffer(tmpbuf, chr)
            count += 1
        end

        if !failed
            str = PL_chars_t(tmpbuf, length(String(copy(tmpbuf))), ENC_UTF8, false)
            rc = PL_unify_text(ld, A3, 0, str, PL_STRING) &&
                 (!vlen || PL_unify_int64(ld, A2, count))
        end
    end

    released = PL_release_stream(ld, s)                     # out:
    return (rc && released) ? FTRUE : FFALSE
end

# PORT: pl-string.c open_string as pl_open_string2_va
# (PRED_IMPL("open_string", 2, open_string, 0))
# DIVERGES: `PL_save_text(BUF_MALLOC)` is a copy of the bytes (Julia's GC owns them); `Sopenmem`'s buffer and
# size are references. A text that is not ISO Latin-1 is made UTF-8 (`PL_mb_text`) and the stream reads UTF-8.
"`open_string(+String, -Stream)` (pl-string.c): a stream that reads the text of `A1`."
function pl_open_string2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    flags = CVT_ATOM | CVT_STRING | CVT_LIST | CVT_EXCEPTION

    text = PL_get_text(ld, A1, flags)
    text === nothing && return FFALSE
    text.encoding === ENC_ISO_LATIN_1 || PL_mb_text(text, REP_UTF8)

    bufp = Ref{Union{Nothing, Vector{UInt8}}}(copy(text.text))
    s = Sopenmem(bufp, Ref(text.length), "rF")
    s === nothing && return FFALSE
    s.encoding = text.encoding
    PL_unify_stream(ld, A2, s) && return FTRUE
    Sclose(s)
    return FFALSE
end

# ── the registration table (pl-string.c BeginPredDefs(strings)) ─────────────────────────────────────
# DIVERGES: upstream registers `strings` after `prims`, before `variant` (pl-ext.c:512); T2's table is
# appended after `attvar` in `_PRED_TABLES` (src/pl-ext.jl), as the dispatch indices of the earlier
# tables stay as they were. Only the predicates T2 has ported are listed.
const PL_predicates_from_strings = (
    PL_extension("atom_string", 2, pl_atom_string2_va, PL_FA_VARARGS),
    PL_extension("string_codes", 2, pl_string_codes2_va, PL_FA_VARARGS),
    PL_extension("string_chars", 2, pl_string_chars2_va, PL_FA_VARARGS),
    PL_extension("string_bytes", 3, pl_string_bytes3_va, PL_FA_VARARGS),
    PL_extension("text_to_string", 2, pl_text_to_string2_va, PL_FA_VARARGS),
    PL_extension("string_length", 2, pl_string_length2_va, PL_FA_VARARGS),     # (pl-prims.c)
    PL_extension(
        "string_concat", 3, pl_string_concat3_va, PL_FA_NONDETERMINISTIC | PL_FA_VARARGS
    ),
    PL_extension(
        "sub_string", 5, pl_sub_string5_va, PL_FA_NONDETERMINISTIC | PL_FA_VARARGS
    ),
    PL_extension(
        "string_code", 3, pl_string_code3_va, PL_FA_NONDETERMINISTIC | PL_FA_VARARGS
    ),
    PL_extension("get_string_code", 3, pl_get_string_code3_va, PL_FA_VARARGS),
    PL_extension("split_string", 4, pl_split_string4_va, PL_FA_VARARGS),
    PL_extension("read_string", 5, pl_read_string5_va, PL_FA_VARARGS),
    PL_extension("read_string", 3, pl_read_string3_va, PL_FA_VARARGS),
    PL_extension("open_string", 2, pl_open_string2_va, PL_FA_VARARGS)
)
