# UPSTREAM: swipl-devel src/pl-list.c @ 8e1bc1110be4
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
# NOT PORTED: `'$memberchk'/3`; dicts (`extract_key`'s `dict_lookup_ptr`: a compound is never a dict, so an
# atom key on one is `type_error(dict, …)`); `CMP_ERROR` and `CMP_INCOMPARABLE` from a comparison (the kernel's
# standard order raises neither: src/pl-prims.jl `compare_std_cells`).

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

    len = PL_get_intptr(ld, A2)
    if len !== nothing                                  # PL_get_intptr(A2, &len)
        if len > 0
            list = PL_new_term_ref(ld)

            ensureGlobalSpace(ld, 3 * len) || return FFALSE    # !ensureGlobalSpace(len*3) (L1f f2)

            p0 = allocGlobalCells!(ld, 3 * len)         # p = allocGlobal(len*3) (L1e e4: on the cells)
            ld.slots[list + 1] = consPtr(p0, TAG_COMPOUND | STG_GLOBAL)   # setHandle(list, consPtr(p, …))
            for i in 0:(len - 1)
                q = p0 + 3 * i
                ld.gstack[q] = ld.functor_dot2          # p[0] = FUNCTOR_dot2; setVar(p[1])
                ld.gstack[q + 2] = consPtr(q + 3, TAG_COMPOUND | STG_GLOBAL)   # p[2] = consPtr(&p[3], …)
            end
            ld.gstack[p0 + 3 * len - 1] = ld.atom_nil_w     # p[-1] = ATOM_nil

            return PL_unify(ld, A1, list) ? FTRUE : FFALSE
        elseif len == 0
            return PL_unify_nil(ld, A1) ? FTRUE : FFALSE
        else
            return FFALSE
        end
    elseif PL_is_integer(ld, A2)                        # PL_is_integer(A2)
        _, w, _ = _deref_loc(ld, -(A2 + 1))             # Word p = valTermRef(A2); deRef(p)
        i = _value_term(ld, w)                          # get_integer(*p, &i): an indirect
        if bigint_value(i) < 0                          # ar_sign_i(&i) < 0
            return FFALSE
        end
        outOfStack!(ld, STACK_OVERFLOW_RAISE, :global)  # (L1f f2) too long for the stacks
        return FFALSE
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

# PORT: pl-list.c List_Record as List_Record_cells
# DIVERGES: the records of ONE sort, as three vectors, where upstream lays an array of
# `struct List_Record` on the global stack: a `list` (a pointer to a record) is an index, `NIL` is
# 0, and the last index is `nat_sort`'s `header`. `term[i]` and `key[i]` are the dereferenced GLOBAL
# positions of the item and its key (upstream: pointers to those cells).
"The records of a sort on cells: record `i` is `next[i]`, the item at `term[i]`, its key at `key[i]`."
struct List_Record_cells
    next::Vector{Int}
    term::Vector{Int}
    key::Vector{Int}
end

# The `compare(c, x, y)` macro of pl-list.c: the order of two records' keys, reversed for a
# descending sort. Upstream's returns from `nat_sort` on `CMP_ERROR`/`CMP_INCOMPARABLE`; the
# kernel's standard order returns neither.
function _sort_compare(
    ld::PL_local_data{T}, L::List_Record_cells, x::Int, y::Int, order::sort_order
)::Int where {T}
    c = compareStandard_cells(ld, L.key[x], L.key[y], false)    # COMPARE_KEY, on the cells
    order == SORT_DESC && (c = -c)
    return c
end

# PORT: pl-list.c nat_sort
# DIVERGES: records are indices into `L` (see `List_Record_cells`); `FREE` — which leaves a dropped
# record as three variables on the global stack — has nothing to do; no `culprit`, no `err` (see
# `_sort_compare`). The run stack is upstream's 64 entries.
"""
    nat_sort(ld, L, data, remove_dups, order) -> Int

Sort the records chained from `data` by their keys (pl-list.c `nat_sort`: a bottom-up natural
merge sort, stable); drop a record whose key equals an earlier one's when `remove_dups`. The
first record of the sorted chain, 0 for none.
"""
function nat_sort(
    ld::PL_local_data{T}, L::List_Record_cells, data::Int,
    remove_dups::Bool,
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

# PORT: pl-list.c list_sort
"What `prolog_list_to_sort_list_cells` found (pl-list.c `list_sort`)."
@enum list_sort::UInt8 begin
    SORT_ERR
    SORT_SORT
    SORT_NIL
    SORT_NOSORT
end


# ── on the CELLS (L1d step 9; the workspace's L1_plan/stageL1d_design.md §3i) ─────────────────────
# The records hold the items' and keys' positions and are compared by the standard order on cells;
# the sorted list is laid out as fresh cells at gTop (upstream rewrites the records, which it laid
# at gTop, in place): a representation-only DIVERGES.

# PORT: pl-list.c extract_key as extract_key_cells
# (the non-pair path)
# DIVERGES: on the cells: `p1` and the result are DEREFERENCED global positions; `argv` is a `Vector` of keys (an `Int`:
# the argument's number; an atom: a dict key — upstream's tagged-integer and atom WORDS, which an integer is not in
# every term type); the error cases leave their error raised and return `nothing`. NOT PORTED: dicts (`termIsDict`/`dict_lookup_ptr`): an atom key on a compound is
# `type_error(dict, …)`, as for a compound that is no dict.
"The position of the key of the item at `p1`: the argument path `argv` followed (pl-list.c `extract_key`)."
function extract_key_cells(
    ld::PL_local_data{T}, p1::Int, argv::Vector{Union{Int, T}}
)::Union{Nothing, Int} where {T}
    for key in argv
        k, w, _ = _deref_loc(ld, p1)
        expected = "compound"
        if k == DU_WORD && _is_gcompound(w)
            if key isa Int                              # isInteger(argv[0])
                arity = arityFunctor(ld.functors, ld.gstack[valPtr(w)])
                an = key
                if an <= arity
                    _, _, p1 = _deref_loc(ld, valPtr(w) + an)   # argTermP(*p1, an-1); deRef
                    continue
                end
                err_t = PL_new_term_ref(ld)             # pushWordAsTermRef(p1)
                ld.slots[err_t + 1] = makeRefG(p1)
                ant = PL_new_term_ref(ld)
                PL_put_integer(ld, ant, an)             # *valTermRef(ant) = argv[0]
                PL_existence_error3(ld, mk_sym(T, :argument), ant, err_t)
                PL_reset_term_refs(ld, err_t)           # popTermRef()
                return nothing
            end
            expected = "dict"                           # no dict, atom key
        end
        err_t = PL_new_term_ref(ld)
        ld.slots[err_t + 1] = makeRefG(p1)
        PL_type_error(ld, expected, err_t)
        PL_reset_term_refs(ld, err_t)
        return nothing
    end
    return p1
end

# PORT: pl-list.c prolog_list_to_sort_list as prolog_list_to_sort_list_cells
# DIVERGES: returns `(what, records)` where upstream writes the records' start and end through
# `lp` and `end`; the records hold the items' and keys' positions, one more record than the elements:
# `nat_sort`'s header. `argv` is a `Vector` of key words (`argc` is its length): tagged integers and atoms.
"The list term reference `t` holds as sort records on cells (pl-list.c)."
function prolog_list_to_sort_list_cells(
    ld::PL_local_data{T}, t::term_t, remove_dups::Bool, pair::Bool,
    argv::Vector{Union{Int, T}}=Union{Int, T}[]
)::Tuple{list_sort, Union{Nothing, List_Record_cells}} where {T}
    len, tk, tw, _ = skip_list_cells(ld, -(t + 1))
    tnil = tk == DU_WORD && tw == ld.atom_nil_w
    tlist = _is_list_word(ld, tk, tw)
    if !(tnil ||                                        # proper list
         (tlist && remove_dups))                        # sort/2 on cyclic list
        if tk == DU_CELL
            PL_error(ld, ERR_INSTANTIATION)
        else
            PL_error(ld, ERR_TYPE, mk_sym(T, :list), t)
        end
        return (SORT_ERR, nothing)
    end
    len == 0 && return (SORT_NIL, nothing)
    len == 1 && !pair && isempty(argv) && !tlist && return (SORT_NOSORT, nothing)
    L = List_Record_cells(
        Vector{Int}(undef, len + 1), Vector{Int}(undef, len), Vector{Int}(undef, len)
    )
    minus2 =
        pair ? lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :-)), 2) : word(0)
    _, lw, _ = _deref_loc(ld, -(t + 1))
    for p in 1:len
        k, w, ip = _deref_loc(ld, valPtr(lw) + 1)      # HeadList(l); deRef
        kp = ip                                         # extract_key
        if !pair
            kp = extract_key_cells(ld, ip, argv)
            kp === nothing && return (SORT_ERR, nothing)
        else
            if k == DU_WORD && _is_gcompound(w) && ld.gstack[valPtr(w)] == minus2
                _, _, kp = _deref_loc(ld, valPtr(w) + 1)    # argTermP(*p1, 0); deRef(p1)
            else
                err_t = PL_new_term_ref(ld)             # pushWordAsTermRef(p1)
                ld.slots[err_t + 1] = makeRefG(ip)
                PL_error(ld, "keysort", 2, "", ERR_TYPE, mk_sym(T, :pair), err_t)
                PL_reset_term_refs(ld, err_t)           # popTermRef()
                return (SORT_ERR, nothing)
            end
        end
        L.term[p] = ip
        L.key[p] = kp
        _, lw, _ = _deref_loc(ld, valPtr(lw) + 2)      # TailList(l); deRef
        L.next[p] = p < len ? p + 1 : 0
    end
    L.next[len + 1] = 0                                 # (the header)
    return (SORT_SORT, L)
end

# PORT: pl-list.c put_sort_list as put_sort_list_cells
# DIVERGES: a fresh run of `'[|]'/2` cells at gTop (see the section header); the head as `linkVal`:
# a reference for a variable, else the item's word.
"Make term reference `l` hold the list of the items of the records chained from `sl`, as cells (pl-list.c)."
function put_sort_list_cells(
    ld::PL_local_data{T}, l::term_t, L::List_Record_cells, sl::Int
)::Nothing where {T}
    n = 0
    s = sl
    while s != 0
        n += 1
        s = L.next[s]
    end
    base = allocGlobalCells!(ld, 3 * n)
    b = base
    while true
        nx = L.next[sl]
        ip = L.term[sl]
        c = ld.gstack[ip]
        ld.gstack[b + 1] = isVar(c) ? makeRefG(ip) : c  # needsRef(*item) ? makeRefG(item) : *item
        ld.gstack[b] = ld.functor_dot2
        if nx != 0
            ld.gstack[b + 2] = consPtr(b + 3, TAG_COMPOUND | STG_GLOBAL)
            sl = nx
            b += 3
        else
            ld.gstack[b + 2] = ld.atom_nil_w
            break
        end
    end
    ld.gstack[unRef(ld.slots[l + 1])] = consPtr(base, TAG_COMPOUND | STG_GLOBAL)   # *valTermRef(l)
    return nothing
end

# PORT: pl-list.c pl_nat_sort
# DIVERGES: on the cells (above); `argv` as `prolog_list_to_sort_list_cells`'s.
"Unify `out` with the list `in_` sorted (pl-list.c `pl_nat_sort`): by its keys when `pair`, by the argument path `argv` (sort/4), without duplicates when `remove_dups`."
function pl_nat_sort(
    ld::PL_local_data{T}, in_::term_t, out::term_t, remove_dups::Bool, order::sort_order,
    pair::Bool, argv::Vector{Union{Int, T}}=Union{Int, T}[]
)::Bool where {T}
    what, L = prolog_list_to_sort_list_cells(ld, in_, remove_dups, pair, argv)
    if what == SORT_ERR
        return false
    elseif what == SORT_NIL
        return PL_unify_nil(ld, out)
    elseif what == SORT_NOSORT
        return PL_unify(ld, in_, out)
    end
    tmp = new_term_ref(ld)                              # a fresh global cell, referenced
    recs = L::List_Record_cells
    l = nat_sort(ld, recs, 1, remove_dups, order)
    put_sort_list_cells(ld, tmp, recs, l)
    return PL_unify(ld, out, tmp)
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

# PORT: pl-list.c get_key_arg_ex
# DIVERGES: returns `(rc, key)` where upstream returns `rc` (true, false, -1) and writes the key word through `k`: the key
# is an `Int` or an atom here (see `extract_key_cells`). A positive integer beyond the TAGGED range makes upstream
# return `false` WITHOUT an error (its `ar_sign_i(&n) <= 0` guards only the error): kept.
"The key `t` holds as a sort key: a positive integer (or 0 when `zero_ok`) or an atom (pl-list.c `get_key_arg_ex`); `rc` -1: neither."
function get_key_arg_ex(
    ld::PL_local_data{T}, t::term_t, zero_ok::Bool
)::Tuple{Int, Union{Nothing, Int, T}} where {T}
    if PL_is_integer(ld, t)                             # isTaggedInt, then isInteger(*p)
        _, w, _ = _deref_loc(ld, -(t + 1))
        n = isTaggedIntW(w) ? valInt(w) : bigint_value(_value_term(ld, w))
        tagged = n isa Int64 && valInt(consInt(n)) == n
        tagged && n > 0 && return (1, Int(n))
        tagged && n == 0 && zero_ok && return (1, 0)
        n <= 0 && PL_error(ld, ERR_DOMAIN, mk_sym(T, :not_less_than_one), t)
        return (0, nothing)
    end
    a = PL_get_atom(ld, t)
    a === nothing || return (1, a)
    return (-1, nothing)
end

# PORT: pl-list.c order_defs
"The `order` names of sort/4: `(name, order, remove_dups)` (pl-list.c `order_defs`)."
const order_defs = (
    ("<", SORT_ASC, true), ("@<", SORT_ASC, true), ("=<", SORT_ASC, false),
    ("@=<", SORT_ASC, false), (">", SORT_DESC, true), ("@>", SORT_DESC, true),
    (">=", SORT_DESC, false), ("@>=", SORT_DESC, false)
)

# PORT: pl-list.c sort as pl_sort4_va
# (PRED_IMPL("sort", 4, sort, 0))
"`sort(+Key, +Order, +List, -Sorted)`: ECLiPSe-compatible sort on a key (pl-list.c)."
function pl_sort4_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3, A4 = PL__t0, PL__t0 + 1, PL__t0 + 2, PL__t0 + 3
    argv = Union{Int, T}[]
    rc, key = get_key_arg_ex(ld, A1, true)
    if rc == 0
        return FFALSE
    elseif rc == 1                                      # Key is integer (or atom)
        key === 0 || push!(argv, key)                   # argv[0] == consInt(0): argc = 0
    else
        type, _ = PL_skip_list(ld, A1)
        if type != PL_LIST
            PL_type_error(ld, "sort_key", A1)
            return FFALSE
        end
        tail = PL_copy_term_ref(ld, A1)
        head = PL_new_term_ref(ld)
        while PL_get_list(ld, tail, head, tail)
            r, k = get_key_arg_ex(ld, head, false)
            r == 1 || return FFALSE
            push!(argv, k)
        end
    end
    order_name = PL_get_atom_ex(ld, A2)
    order_name === nothing && return FFALSE
    on = kind(order_name) === SYM ? sym_text(order_name) : ""
    for (name, order, remove_dups) in order_defs
        if name == on
            return pl_nat_sort(ld, A3, A4, remove_dups, order, false, argv) ? FTRUE : FFALSE
        end
    end
    PL_domain_error(ld, "order", A2)
    return FFALSE
end

# PORT: pl-list.c BeginPredDefs as PL_predicates_from_list
# DIVERGES: the ported entries (upstream's table also has `'$memberchk'/3`).
"pl-list.c's registration table (`BeginPredDefs(list)`): the ported entries."
const PL_predicates_from_list = (
    PL_extension("is_list", 1, pl_is_list1_va, PL_FA_VARARGS),
    PL_extension("\$length", 2, pl_dlength2_va, PL_FA_VARARGS),
    PL_extension("sort", 2, pl_sort2_va, PL_FA_VARARGS | PL_FA_ISO),
    PL_extension("msort", 2, pl_msort2_va, PL_FA_VARARGS),
    PL_extension("keysort", 2, pl_keysort2_va, PL_FA_VARARGS | PL_FA_ISO),
    PL_extension("sort", 4, pl_sort4_va, PL_FA_VARARGS)
)
