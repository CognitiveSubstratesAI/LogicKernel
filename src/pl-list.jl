# UPSTREAM: swipl-devel src/pl-list.c @ 8609e216cab9
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# LISTS (pl-list.c): `is_list/1`, `'$length'/2` — the "length is known" path of boot/init.pl's
# length/2 — and the sorts, `sort/2`, `msort/2` and `keysort/2`, over Richard O'Keefe's natural
# merge sort (`nat_sort`), ported line for line: it takes the runs the list already has, so a
# sorted list costs one pass, and it is stable, which keysort/2 requires.
#
# NOT PORTED: `sort/4` (`get_key_arg_ex`, `order_defs`, and `extract_key`'s argument path, with its
# dicts), `'$memberchk'/3`; `CMP_ERROR` and `CMP_INCOMPARABLE` from a comparison (the kernel's
# standard order raises neither: src/pl-prims.jl `compare_std`).

# PORT: pl-list.c is_list as pl_is_list1_va
# (PRED_IMPL("is_list", 1, is_list, 0))
"`is_list(@Term)`: `Term` is a proper list (pl-list.c)."
function pl_is_list1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    if lengthList(ld, A1, false) >= 0
        return FTRUE
    end

    return FFALSE
end

# PORT: pl-list.c dlength as pl_dlength2_va
# (PRED_IMPL("$length", 2, dlength, 0))
# DIVERGES: the list is built from its end, of fresh variables whose keys are in list order (the
# order of upstream's cells). NOT PORTED: the global stack's overflow — upstream raises a resource
# error for a list that does not fit the stacks (`ensureGlobalSpace`, and `outOfStack` for a big
# integer); with no global stack such a length is refused (`NotPortedError`) rather than built.
"`'\$length'(-List, +Len)`: `List` is a list of `Len` fresh variables; fails if `Len < 0` (pl-list.c)."
function pl_dlength2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    p = deRef(ld, ld.slots[A2 + 1])

    if isInteger(p) && integer_is_int64(p)              # PL_get_intptr(A2, &len)
        len = Int(int64_value(p))
        if len > 0
            list = PL_new_term_ref(ld)

            if len > ld.stacks_limit ÷ 3                # !ensureGlobalSpace(len*3, ALLOW_GC)
                throw(
                    NotPortedError{T}(
                        p, "a list longer than the stacks (the global stack's overflow)",
                        "L1"
                    )
                )
            end

            k = allocGlobalVars!(ld, len)
            dot = mk_sym(T, LIST_CONS_NAME)
            l = mk_nil(T)                               # p[-1] = ATOM_nil
            for i in len:-1:1
                l = mk_expr(T, T[dot, mk_var(T, k + UInt64(i - 1)), l])
            end
            ld.slots[list + 1] = l

            return PL_unify(ld, A1, list) ? FTRUE : FFALSE
        elseif len == 0
            return PL_unify_nil(ld, A1) ? FTRUE : FFALSE
        else
            return FFALSE
        end
    elseif isInteger(p)                                 # PL_is_integer(A2)
        if bigint_value(p) < 0                          # ar_sign_i(&i) < 0
            return FFALSE
        end

        throw(
            NotPortedError{T}(
                p, "a list longer than the stacks (the global stack's overflow)", "L1"
            )
        )
    end

    return PL_error(ld, "length", 2, "", ERR_TYPE, mk_sym(T, :integer), A2) ? FTRUE : FFALSE
end

# ── the sorts (pl-list.c) ────────────────────────────────────────────────────────────────────────

# PORT: pl-list.c sort_order
"The direction of a sort (pl-list.c `sort_order`)."
@enum sort_order::UInt8 begin
    SORT_ASC = 0
    SORT_DESC = 1
end

# PORT: pl-list.c List_Record
# DIVERGES: the records of ONE sort, as three vectors, where upstream lays an array of
# `struct List_Record` on the global stack: a `list` (a pointer to a record) is an index, `NIL` is
# 0, and the last index is `nat_sort`'s `header`. `term` and `key` are the dereferenced terms
# (upstream: pointers to their cells).
"The records of a sort (pl-list.c `struct List_Record`): record `i` is `next[i]`, `term[i]`, `key[i]`."
struct List_Record{T}
    next::Vector{Int}
    term::Vector{T}
    key::Vector{T}
end

# The `compare(c, x, y)` macro of pl-list.c: the order of two records' keys, reversed for a
# descending sort. Upstream's returns from `nat_sort` on `CMP_ERROR`/`CMP_INCOMPARABLE`; the
# kernel's standard order returns neither.
function _sort_compare(
    ld::PL_local_data{T}, L::List_Record{T}, x::Int, y::Int, order::sort_order
)::Int where {T}
    c = compareStandard(ld, L.key[x], L.key[y], false)  # COMPARE_KEY(&(x)->item, &(y)->item)
    order == SORT_DESC && (c = -c)
    return c
end

# PORT: pl-list.c nat_sort
# DIVERGES: records are indices into `L` (see `List_Record`); `FREE` — which leaves a dropped
# record as three variables on the global stack — has nothing to do; no `culprit`, no `err` (see
# `_sort_compare`). The run stack is upstream's 64 entries.
"""
    nat_sort(ld, L, data, remove_dups, order) -> Int

Sort the records chained from `data` by their keys (pl-list.c `nat_sort`: a bottom-up natural
merge sort, stable); drop a record whose key equals an earlier one's when `remove_dups`. The
first record of the sorted chain, 0 for none.
"""
function nat_sort(
    ld::PL_local_data{T}, L::List_Record{T}, data::Int, remove_dups::Bool,
    order::sort_order
)::Int where {T}
    stack = Vector{Int}(undef, 64)              # enough for biggest machine
    sp = 0
    runs = 0                                    # total number of runs processed
    p = q = r = s = 0
    header = length(L.next)
    next = L.next

    rd = remove_dups ? 0 : 1                    # 0 -> do, 1 -> don't
    while (p = data) != 0
        # pick up a run from the front of data, setting
        # p = (pointer to beginning of run), data = (rest of data)
        if (q = next[p]) != 0
            c = _sort_compare(ld, L, p, q, order)

            data = next[q]
            if c > 0
                r = q
                q = p
                p = r
                next[p] = q
            elseif c == rd
                # c < 0 or = 0, so c = 1 impossible
                next[p] = next[q]
                q = p                           # FREE(q)
            end

            r = data
            while r != 0
                c = _sort_compare(ld, L, q, r, order)

                if c > 0
                    break
                end
                if c == rd
                    s = next[r]
                    r = s                       # FREE(r)
                else
                    next[q] = r
                    q = r
                    r = next[r]
                end
            end

            next[q] = 0
            data = r
        else
            data = 0
        end

        runs += 1
        # merge this run with 0 or more runs off the top of the stack
        k = runs
        while (1 & ~k) != 0
            q = stack[sp]
            sp -= 1
            r = header
            while q != 0 && p != 0
                # q precedes p
                c = _sort_compare(ld, L, q, p, order)

                if c <= 0
                    next[r] = q
                    r = q
                    q = next[q]
                    if c == rd
                        s = next[p]
                        p = s                   # FREE(p)
                    end
                else
                    next[r] = p
                    r = p
                    p = next[p]
                end
            end
            next[r] = q != 0 ? q : p
            p = next[header]
            k >>= 1
        end

        # push the merged run onto the stack
        sp += 1
        stack[sp] = p
    end

    if sp == 0
        return 0
    end

    # merge all the runs on the stack
    p = stack[sp]
    sp -= 1
    while sp != 0
        q = stack[sp]
        sp -= 1
        r = header
        while q != 0 && p != 0
            # q precedes p
            c = _sort_compare(ld, L, q, p, order)

            if c <= 0
                next[r] = q
                r = q
                q = next[q]
                if c == rd
                    s = next[p]
                    p = s                       # FREE(p)
                end
            else
                next[r] = p
                r = p
                p = next[p]
            end
        end
        next[r] = q != 0 ? q : p
        p = next[header]
    end

    return p
end

# PORT: pl-list.c extract_key
# DIVERGES: returns the key, or `nothing` with the error raised. NOT PORTED: `argc`/`argv` — the
# argument path of sort/4, dicts included: without `pair` the key is the term.
"The key of list element `p1`: the first argument of a `Key-Value` pair when `pair`, else `p1` (pl-list.c)."
function extract_key(ld::PL_local_data{T}, p1::T, pair::Bool)::Union{Nothing, T} where {T}
    if pair
        if _hasFunctor(p1, mk_sym(T, :-), 2)            # hasFunctor(*p1, FUNCTOR_minus2)
            return deRef(ld, child(p1, 2))              # argTermP(*p1, 0); deRef(p1)
        else
            err_t = PL_new_term_ref(ld)                 # pushWordAsTermRef(p1)
            ld.slots[err_t + 1] = p1

            PL_error(ld, "keysort", 2, "", ERR_TYPE, mk_sym(T, :pair), err_t)
            PL_reset_term_refs(ld, err_t)               # popTermRef()
            return nothing
        end
    end

    return p1
end

# PORT: pl-list.c list_sort
"What `prolog_list_to_sort_list` found (pl-list.c `list_sort`)."
@enum list_sort::UInt8 begin
    SORT_ERR
    SORT_SORT
    SORT_NIL
    SORT_NOSORT
end

# PORT: pl-list.c prolog_list_to_sort_list
# DIVERGES: returns `(what, records)` where upstream writes the records' start and end through
# `lp` and `end`; the records are allocated here (upstream: on the global stack, where the result
# will be), one more than the elements: `nat_sort`'s header. NOT PORTED: `argc`/`argv` (sort/4).
"""
The elements of the list term reference `t` holds, as sort records (pl-list.c): `SORT_ERR` with the
error raised for a partial list or a non-list, `SORT_NIL` for `[]`, `SORT_NOSORT` for one element
that needs no key. A cyclic list is sorted when `remove_dups`.
"""
function prolog_list_to_sort_list(
    ld::PL_local_data{T}, t::term_t, remove_dups::Bool, pair::Bool
)::Tuple{list_sort, Union{Nothing, List_Record{T}}} where {T}
    len, tail = skip_list(ld, ld.slots[t + 1])
    if !(is_nil(tail) ||                                # proper list
         (is_pair(tail) && remove_dups))                # sort/2 on cyclic list
        if kind(tail) === VAR
            PL_error(ld, ERR_INSTANTIATION)
        else
            PL_error(ld, ERR_TYPE, mk_sym(T, :list), t)
        end

        return (SORT_ERR, nothing)
    end

    if len == 0
        return (SORT_NIL, nothing)
    end
    if len == 1 && !pair && !is_pair(tail)
        return (SORT_NOSORT, nothing)
    end

    L = List_Record{T}(
        Vector{Int}(undef, len + 1), Vector{T}(undef, len), Vector{T}(undef, len)
    )

    l = deRef(ld, ld.slots[t + 1])
    for p in 1:len
        item = deRef(ld, child(l, 2))                   # HeadList(l)
        key = extract_key(ld, item, pair)

        if key === nothing
            return (SORT_ERR, nothing)
        end
        L.term[p] = item
        L.key[p] = key

        l = deRef(ld, child(l, 3))                      # TailList(l)
        L.next[p] = p < len ? p + 1 : 0
    end
    L.next[len + 1] = 0                                 # (the header)

    return (SORT_SORT, L)
end

# PORT: pl-list.c put_sort_list
# DIVERGES: the list is built from its end (upstream turns the records themselves into the list's
# cells, in place).
"Make term reference `l` hold the list of the terms of the records chained from `sl` (pl-list.c)."
function put_sort_list(
    ld::PL_local_data{T}, l::term_t, L::List_Record{T}, sl::Int
)::Nothing where {T}
    items = T[]
    while sl != 0
        push!(items, L.term[sl])
        sl = L.next[sl]
    end
    dot = mk_sym(T, LIST_CONS_NAME)
    list = mk_nil(T)
    for i in length(items):-1:1
        list = mk_expr(T, T[dot, items[i], list])
    end
    ld.slots[l + 1] = list
    return nothing
end

# PORT: pl-list.c pl_nat_sort
# DIVERGES: no local space to ensure, no `gTop` to reset; a comparison raises nothing (see
# `_sort_compare`). NOT PORTED: `argc`/`argv` (sort/4).
"Unify `out` with the list `in_` sorted (pl-list.c `pl_nat_sort`): by its keys when `pair`, without duplicates when `remove_dups`."
function pl_nat_sort(
    ld::PL_local_data{T}, in_::term_t, out::term_t, remove_dups::Bool, order::sort_order,
    pair::Bool
)::Bool where {T}
    what, L = prolog_list_to_sort_list(ld, in_, remove_dups, pair)
    if what == SORT_ERR
        return false
    elseif what == SORT_NIL
        return PL_unify_nil(ld, out)
    elseif what == SORT_NOSORT
        return PL_unify(ld, in_, out)
    else
        tmp = PL_new_term_ref(ld)

        recs = L::List_Record{T}
        l = nat_sort(ld, recs, 1, remove_dups, order)
        put_sort_list(ld, tmp, recs, l)

        return PL_unify(ld, out, tmp)
    end
end

# PORT: pl-list.c sort as pl_sort2_va
# (PRED_IMPL("sort", 2, sort, PL_FA_ISO))
"`sort(+List, -Sorted)`: the standard order, duplicates removed (pl-list.c)."
function pl_sort2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1

    return pl_nat_sort(ld, A1, A2, true, SORT_ASC, false) ? FTRUE : FFALSE
end

# PORT: pl-list.c msort as pl_msort2_va
# (PRED_IMPL("msort", 2, msort, 0))
"`msort(+List, -Sorted)`: the standard order, duplicates kept (pl-list.c)."
function pl_msort2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1

    return pl_nat_sort(ld, A1, A2, false, SORT_ASC, false) ? FTRUE : FFALSE
end

# PORT: pl-list.c keysort as pl_keysort2_va
# (PRED_IMPL("keysort", 2, keysort, PL_FA_ISO))
"`keysort(+Pairs, -Sorted)`: `Key-Value` pairs by the standard order of their keys, stable (pl-list.c)."
function pl_keysort2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1

    return pl_nat_sort(ld, A1, A2, false, SORT_ASC, true) ? FTRUE : FFALSE
end

# PORT: pl-list.c BeginPredDefs as PL_predicates_from_list
# DIVERGES: the ported entries (upstream's table also has `'$memberchk'/3` and `sort/4`).
"pl-list.c's registration table (`BeginPredDefs(list)`): the ported entries."
const PL_predicates_from_list = (
    PL_extension("is_list", 1, pl_is_list1_va, PL_FA_VARARGS),
    PL_extension("\$length", 2, pl_dlength2_va, PL_FA_VARARGS),
    PL_extension("sort", 2, pl_sort2_va, PL_FA_VARARGS | PL_FA_ISO),
    PL_extension("msort", 2, pl_msort2_va, PL_FA_VARARGS),
    PL_extension("keysort", 2, pl_keysort2_va, PL_FA_VARARGS | PL_FA_ISO)
)
