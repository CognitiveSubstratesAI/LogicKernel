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

# ── the registration table (pl-string.c BeginPredDefs(strings)) ─────────────────────────────────────
# DIVERGES: upstream registers `strings` after `prims`, before `variant` (pl-ext.c:512); T2's table is
# appended after `attvar` in `_PRED_TABLES` (src/pl-ext.jl), as the dispatch indices of the earlier
# tables stay as they were. Only the predicates T2 has ported are listed.
const PL_predicates_from_strings = (
    PL_extension("atom_string", 2, pl_atom_string2_va, PL_FA_VARARGS),
    PL_extension("string_codes", 2, pl_string_codes2_va, PL_FA_VARARGS),
    PL_extension("string_chars", 2, pl_string_chars2_va, PL_FA_VARARGS),
    PL_extension("text_to_string", 2, pl_text_to_string2_va, PL_FA_VARARGS)
)
