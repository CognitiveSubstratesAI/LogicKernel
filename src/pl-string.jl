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

# ── the registration table (pl-string.c BeginPredDefs(strings)) ─────────────────────────────────────
# DIVERGES: upstream registers `strings` after `prims`, before `variant` (pl-ext.c:512); T2's table is
# appended after `attvar` in `_PRED_TABLES` (src/pl-ext.jl), as the dispatch indices of the earlier
# tables stay as they were. Only the predicates T2 has ported are listed.
const PL_predicates_from_strings = (
    PL_extension("atom_string", 2, pl_atom_string2_va, PL_FA_VARARGS),
    PL_extension("string_codes", 2, pl_string_codes2_va, PL_FA_VARARGS),
    PL_extension("string_chars", 2, pl_string_chars2_va, PL_FA_VARARGS),
    PL_extension("text_to_string", 2, pl_text_to_string2_va, PL_FA_VARARGS),
    PL_extension("string_length", 2, pl_string_length2_va, PL_FA_VARARGS),     # (pl-prims.c)
    PL_extension(
        "string_concat", 3, pl_string_concat3_va, PL_FA_NONDETERMINISTIC | PL_FA_VARARGS
    ),
    PL_extension(
        "sub_string", 5, pl_sub_string5_va, PL_FA_NONDETERMINISTIC | PL_FA_VARARGS
    )
)
