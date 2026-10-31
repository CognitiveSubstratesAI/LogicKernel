# UPSTREAM: swipl-devel src/pl-dict.c @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  2013-2026, VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# DICTS (pl-dict.c): the six predicates boot/init.pl calls — `is_dict/1,2`, `dict_create/3`, `put_dict/3`,
# `select_dict/3` and `get_dict/3` — with the helpers each pulls in. A dict is a compound with the functor
# `dict`/(2N+1) (the reserved atom `ATOM_dict`) and the layout of pl-dict.c's header:
#
#   dict/A | tag | value1 | key1 | value2 | key2 | …            (functor cell, then the A arguments)
#
# The kernel's compound is the same cells (`gstack[p]` the functor word, the arguments at `p+1 … p+A`), so
# `arguments[i]` is position `p + 1 + i`. The keys are atoms or small integers and the pairs are sorted by the
# key WORD (`dict_order`): the kernel's words are not swipl's, so the order of the pairs differs from swipl's;
# nothing here depends on it except the order `get_dict/3` enumerates in (upstream: undefined).
#
# NOT PORTED: the reader's dict syntax `Tag{…}` (src/pl-read.jl refuses it) and the writer's dict arm — a dict
# exists only through `dict_create/3` and `put_dict/3`; the dict predicates outside the six (`dict_pairs/3`,
# `put_dict/4`, `del_dict/4`, `get_dict/5`, `:</2`, `>:</2`, `$get_dict_ex/3`,
# `dict_same_keys/2`, `is_most_general_dict/1`, `PL_for_dict`, the functional notation's `./3`); the
# `dict_functors` cache (`lookupFunctorDef` is called each time).

# ORIGINAL: pl-atom.ih `ATOM_dict` (generated from src/ATOMS): the reserved atom `dict` (src/pl-ressymbol.jl retypes it).
"The atom word of the reserved symbol `dict` (pl-atom.ih `ATOM_dict`): the same in every database."
const ATOM_dict = builtin_atom("dict")

# PORT: pl-dict.c dict_functor
# DIVERGES: no `GD->dict.dict_functors` cache for the small arities: the table is asked every time.
"The functor word of a dict with `pairs` key-value pairs: `dict`/(2*pairs+1) (pl-dict.c)."
function dict_functor(ld::PL_local_data, pairs::Int)::word
    return lookupFunctorDef(ld.functors, ATOM_dict, pairs * 2 + 1)
end

# PORT: pl-dict.c is_dict_functor
"Whether functor word `f` is `dict`/N with N odd (pl-dict.c)."
function is_dict_functor(ld::PL_local_data, f::word)::Bool
    return nameFunctor(ld.functors, f) == ATOM_dict &&
           arityFunctor(ld.functors, f) % 2 == 1
end

# PORT: pl-dict.c is_dict_term
# DIVERGES: `(kind, word)` is a dereferenced location's (`_deref_loc`).
"Whether the dereferenced word `w` (of kind `k`) is a compound with a dict functor (pl-dict.c)."
function is_dict_term(ld::PL_local_data, k::UInt8, w::word)::Bool
    if k == DU_WORD && _is_gcompound(w)
        return is_dict_functor(ld, ld.gstack[valPtr(w)])
    end

    return false
end

# PORT: pl-dict.h is_dict_key
"Whether the word `w` is a legal dict key: an atom or a small integer (pl-dict.h)."
is_dict_key(w::word)::Bool = isAtomW(w) || isTaggedIntW(w)

# PORT: pl-dict.c get_dict_ex
# DIVERGES: the dict's word is the result (`*dp`), `nothing` for upstream's false.
"The dict term reference `t` holds, as a compound word; a type error when `ex` and it is no dict (pl-dict.c)."
function get_dict_ex(ld::PL_local_data{T}, t::term_t, ex::Bool)::Union{Nothing, word} where {T}
    k, w, _ = _deref_loc(ld, -(t + 1))
    if is_dict_term(ld, k, w)
        return w
    end

    if !ex
        return nothing
    end

    PL_type_error(ld, "dict", t)
    return nothing
end

# PORT: pl-dict.c dict_lookup_ptr
# DIVERGES: the result is `(value position, pair index)` where upstream returns `p-1`, the value cell, and
# `*arg`; `nothing` for NULL. `dict` is the dict's compound word, `name` a key word.
"The position of the value of key `name` in the dict `dict`, and the pair's index (1-based); a binary search (pl-dict.c)."
function dict_lookup_ptr(
    ld::PL_local_data, dict::word, name::word
)::Union{Nothing, Tuple{Int, Int}}
    f = valPtr(dict)
    arity = arityFunctor(ld.functors, ld.gstack[f])
    l = 1
    h = arity ÷ 2

    if arity == 1
        return nothing                              # empty
    end
    @assert arity % 2 == 1

    while true
        m = (l + h) ÷ 2
        _, p, _ = _deref_loc(ld, f + 1 + m * 2)     # deRef2(&data->arguments[m*2], p)

        if p == name
            return (f + m * 2, m)                   # return p-1; *arg = m
        end

        if l == h
            return nothing
        end

        if p < name
            l = m + 1
        elseif m == l
            h = m
        else
            h = m - 1
        end
    end
end

# PORT: pl-dict.c is_dict as pl_is_dict1_va
# (PRED_IMPL("is_dict", 1, is_dict, 0))
"`is_dict(@Term)`: `Term` is a dict (pl-dict.c)."
function pl_is_dict1_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1 = PL__t0
    k, w, _ = _deref_loc(ld, -(A1 + 1))

    return is_dict_term(ld, k, w) ? FTRUE : FFALSE
end

# PORT: pl-dict.c is_dict as pl_is_dict2_va
# (PRED_IMPL("is_dict", 2, is_dict, 0))
"`is_dict(@Term, ?Tag)`: `Term` is a dict with tag `Tag` (pl-dict.c)."
function pl_is_dict2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2 = PL__t0, PL__t0 + 1
    k, w, _ = _deref_loc(ld, -(A1 + 1))

    if is_dict_term(ld, k, w)
        f = valPtr(w)
        return unify_ptrs_cells(ld, f + 1, -(A2 + 1)) ? FTRUE : FFALSE   # unify_ptrs(&f->arguments[0], valTermRef(A2))
    end

    return FFALSE
end

# ── ordering, creation (part 5b) ──────────────────────────────────────────────────────────────────

# PORT: pl-dict.h _PL_dict_status_t
"What `dict_ordered` and `dict_order` found (pl-dict.h `_PL_dict_status_t`)."
@enum _PL_dict_status_t::Int8 begin
    PL_DICT_FALSE = 0
    PL_DICT_TRUE = 1
    PL_DICT_KEY_INVALID = -1
    PL_DICT_KEY_DUPLICATE = -2
end

# PORT: pl-dict.c DICT_GET_ALL, DICT_GET_PAIRS, DICT_GET_EQUALS, DICT_GET_COLON, DICT_GET_TERM
"`PL_get_dict_ex`' `flags`: which forms of a key-value pair are read (pl-dict.c)."
const DICT_GET_ALL = 0xff
const DICT_GET_PAIRS = 0x01
const DICT_GET_EQUALS = 0x02
const DICT_GET_COLON = 0x04
const DICT_GET_TERM = 0x08

# ORIGINAL: the term reference `ex` raised as `error(duplicate_key(Key), _)`: pl-error.c's `ERR_DUPLICATE_KEY`
# branch, `PL_unify_term(formal, PL_FUNCTOR, FUNCTOR_duplicate_key1, PL_TERM, key)`.
# DIVERGES: a function of its own, not a `PL_error` code (no `ERR_DUPLICATE_KEY` in the enum: pl-dict.c is its only
# caller), as `PL_existence_error3` (src/pl-error.jl).
"Raise `error(duplicate_key(Key), _)`, `Key` the term reference `key` holds (pl-error.c `ERR_DUPLICATE_KEY`); `false`."
function PL_duplicate_key_error(ld::PL_local_data{T}, key::term_t)::Bool where {T}
    h = _PL_error_open(ld)
    h === nothing && return false
    caller, fid, except, formal, swi = h
    PL_cons_functor(ld, formal, _err_functor(ld, :duplicate_key, 1), key)
    return _PL_error_close!(ld, caller, fid, except, formal, swi, "", 0, "")
end

# ORIGINAL: pl-inline.h `*dp = linkValI(val)` for a value LOCATION `loc` (a global position or a slot, `_deref_loc`'s):
# the cell at `dp` holds what `loc` dereferences to — an unbound or attributed variable by reference, a word as it is.
# A value-table word is shared; a slot's side value gets its own word (`_value_word!`).
"Store in global cell `dp` what the location `loc` dereferences to (pl-inline.h `linkValI`)."
function _dict_link!(ld::PL_local_data, dp::Int, loc::Int)::Nothing
    k, w, q = _deref_loc(ld, loc)
    if k == DU_CELL || k == DU_ATTVAR
        ld.gstack[dp] = makeRefG(q)
    elseif k == DU_VALUE
        ld.gstack[dp] = _value_word!(ld, w)
    else
        ld.gstack[dp] = w
    end

    return nothing
end

# PORT: pl-dict.c dict_ordered
# DIVERGES: `data` is the position of the first VALUE cell, the pairs follow; the result is `(status, dupl)`, `dupl` the
# duplicate key's word when `want_dupl` (upstream's `dupl` pointer is not NULL) and else the error is raised here.
"Whether the `count` pairs at `data` have proper keys in order: `(status, duplicate key word)` (pl-dict.c)."
function dict_ordered(
    ld::PL_local_data{T}, data::Int, count::Int, want_dupl::Bool
)::Tuple{_PL_dict_status_t, word} where {T}
    ordered = PL_DICT_TRUE

    if count > 0
        data += 1                                   # skip to key
        _, n1, _ = _deref_loc(ld, data)
        if !is_dict_key(n1)
            return (PL_DICT_KEY_INVALID, word(0))
        end

        while count > 1
            _, n2, _ = _deref_loc(ld, data + 2)
            if !is_dict_key(n2)
                return (PL_DICT_KEY_INVALID, word(0))
            end
            if n1 == n2
                if want_dupl
                    return (PL_DICT_KEY_DUPLICATE, n1)
                else
                    t = PL_new_term_ref(ld)
                    ld.slots[t + 1] = n1            # *valTermRef(t) = linkValI(n1)
                    PL_duplicate_key_error(ld, t)
                    return (PL_DICT_KEY_DUPLICATE, word(0))
                end
            elseif n1 > n2
                ordered = PL_DICT_FALSE
            end
            count -= 1
            data += 2
            n1 = n2
        end
    end

    return (ordered, word(0))
end

# PORT: pl-dict.c compare_dict_entry, dict_order
# DIVERGES: the pairs are sorted by their key WORDS (`SCALAR_TO_CMP` on the dereferenced key cells) with Julia's
# `sortperm` on the keys read out, the cells written back in the new order (upstream: `sort_r` over the cells in
# place); `dict` is the position of the functor cell; the result is `(status, dupl)` as `dict_ordered`'s.
"Sort the pairs of the dict at `dict` by key and check them: `(status, duplicate key word)` (pl-dict.c)."
function dict_order(ld::PL_local_data{T}, dict::Int)::Tuple{_PL_dict_status_t, word} where {T}
    arity = arityFunctor(ld.functors, ld.gstack[dict])
    @assert arity % 2 == 1
    n = arity ÷ 2

    vals = [ld.gstack[dict + 2 + 2 * i] for i in 0:(n - 1)]
    keys = [ld.gstack[dict + 3 + 2 * i] for i in 0:(n - 1)]
    kw = word[_deref_loc(ld, dict + 3 + 2 * i)[2] for i in 0:(n - 1)]
    ord = sortperm(kw)                              # sort_r(…, compare_dict_entry, LD)
    for (j, i) in enumerate(ord)
        ld.gstack[dict + 2 * j] = vals[i]
        ld.gstack[dict + 2 * j + 1] = keys[i]
    end

    return dict_ordered(ld, dict + 2, n, true)
end

# PORT: pl-dict.c get_name_ex
# DIVERGES: the key's word is the result, `nothing` for upstream's false.
"The dict key (an atom or a small integer word) the term reference `t` holds, else a type error (pl-dict.c)."
function get_name_ex(ld::PL_local_data{T}, t::term_t)::Union{Nothing, word} where {T}
    _, p, _ = _deref_loc(ld, -(t + 1))
    if is_dict_key(p)
        return p
    end

    PL_type_error(ld, "dict-key", t)
    return nothing
end

# PORT: pl-dict.c get_name_value
# DIVERGES: the result is `(key word, value location)` — upstream stores `*name` and `*value = linkValI(vp)` through
# its pointers; the caller links the value location into the dict's cell (`_dict_link!`). `nothing` for upstream's false,
# after `Undo(*m)` and the type error. `p` is the position of the list's head cell; the word a type error names is
# that cell, by reference (`pushWordAsTermRef`).
"The key and the value of the pair at `p` (`K-V`, `K=V`, `K:V` or `K(V)` as `flags` allows) (pl-dict.c)."
function get_name_value(
    ld::PL_local_data{T}, p::Int, flags::Int, m::mark
)::Union{Nothing, Tuple{word, Int}} where {T}
    k, w, pp = _deref_loc(ld, p)

    if k == DU_WORD && _is_gcompound(w)
        f = valPtr(w)
        fdef = ld.gstack[f]
        minus2 = lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :-)), 2)
        equals2 = lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :(=))), 2)
        colon2 = lookupFunctorDef(ld.functors, _atom_word!(ld, mk_sym(T, :(:))), 2)

        if (fdef == minus2 && (flags & DICT_GET_PAIRS) != 0) ||
           (fdef == equals2 && (flags & DICT_GET_EQUALS) != 0) ||
           (fdef == colon2 && (flags & DICT_GET_COLON) != 0)
            _, np, npos = _deref_loc(ld, f + 1)     # deRef2(&f->arguments[0], np)
            if is_dict_key(np)
                return (np, f + 2)                  # *name = *np; *value = linkValI(&f->arguments[1])
            else
                Undo!(ld, m)
                DiscardMark(ld, m)
                t = PL_new_term_ref(ld)             # pushWordAsTermRef(np)
                ld.slots[t + 1] = makeRefG(npos)
                PL_type_error(ld, "dict-key", t)
                PL_reset_term_refs(ld, t)           # popTermRef()

                return nothing
            end
        elseif arityFunctor(ld.functors, fdef) == 1 && (flags & DICT_GET_TERM) != 0   # Name(Value)
            return (nameFunctor(ld.functors, fdef), f + 1)
        end
    end

    type = flags == DICT_GET_PAIRS ? "pair" : "key-value"

    Undo!(ld, m)
    DiscardMark(ld, m)
    t = PL_new_term_ref(ld)                         # pushWordAsTermRef(p)
    ld.slots[t + 1] = makeRefG(pp)
    PL_type_error(ld, type, t)
    PL_reset_term_refs(ld, t)

    return nothing                                  # type error
end

# PORT: pl-dict.c PL_is_dict
# DIVERGES: the dict of the term reference `t`, ordered (`dict_ordered` TRUE); a Bool as upstream's.
"Whether the term reference `t` holds a dict with ordered, proper keys (pl-dict.c)."
function PL_is_dict(ld::PL_local_data{T}, t::term_t)::Bool where {T}
    k, w, _ = _deref_loc(ld, -(t + 1))
    if k == DU_WORD && _is_gcompound(w)
        f = valPtr(w)
        if is_dict_functor(ld, ld.gstack[f])
            arity = arityFunctor(ld.functors, ld.gstack[f])
            return dict_ordered(ld, f + 2, arity ÷ 2, true)[1] == PL_DICT_TRUE   # f->arguments+1
        end
    end

    return false
end

# PORT: pl-dict.c PL_get_dict_ex
# DIVERGES: `tag` is 0 for upstream's NULL; no trail check (the trail grows on demand); the mark is discarded
# on success (`DiscardMark`) where upstream leaves `mark_bar` raised. NOT PORTED: `{name:value, …}` (upstream's TBD).
"`dict` is the dict `data` holds, or the dict made of the list `data` holds; false with the error raised (pl-dict.c)."
function PL_get_dict_ex(
    ld::PL_local_data{T}, data::term_t, tag::term_t, dict::term_t, flags::Int
)::Bool where {T}
    if PL_is_dict(ld, data)
        PL_put_term(ld, dict, data)
        return true
    end

    if PL_is_list(ld, data)
        len = lengthList(ld, data, true)
        len < 0 && return false                     # not a proper list

        ensureGlobalSpace(ld, len * 2 + 2) || return false
        m = Mark(ld)
        dp = allocGlobalCells!(ld, len * 2 + 2)
        ap = dp
        ld.gstack[ap] = dict_functor(ld, len)       # *ap++ = dict_functor(len)
        ap += 1
        if tag != 0
            k, w, cp = _deref_loc(ld, -(tag + 1))
            if k == DU_CELL
                ld.gstack[ap] = word(0)             # setVar(*ap)
                _bind_const!(ld, cp, makeRefG(ap))  # Trail(cp, makeRefG(ap))
            elseif k == DU_ATTVAR
                ld.gstack[ap] = makeRefG(cp)
            elseif k == DU_VALUE
                ld.gstack[ap] = _value_word!(ld, w)
            else
                ld.gstack[ap] = w
            end
        end
        ap += 1

        k, w, _ = _deref_loc(ld, -(data + 1))
        while _is_list_word(ld, k, w)
            head = valPtr(w) + 1                    # HeadList(tail)
            nv = get_name_value(ld, head, flags, m)
            nv === nothing && return false
            name, vloc = nv
            ld.gstack[ap + 1] = name
            _dict_link!(ld, ap, vloc)
            ap += 2
            k, w, _ = _deref_loc(ld, valPtr(w) + 2) # TailList(tail); deRef
        end

        rc, dupl = dict_order(ld, dp)
        if rc == PL_DICT_TRUE
            DiscardMark(ld, m)
            ld.slots[dict + 1] = consPtr(dp, TAG_COMPOUND | STG_GLOBAL)
            return true
        else
            @assert rc == PL_DICT_KEY_DUPLICATE
            Undo!(ld, m)
            DiscardMark(ld, m)
            ex = PL_new_term_ref(ld)
            ld.slots[ex + 1] = dupl                 # PL_unify_atomic(ex, dupl)
            return PL_duplicate_key_error(ld, ex)
        end
    end                                             # TBD: {name:value, ...}

    return PL_type_error(ld, "dict-data", data)
end

# PORT: pl-dict.c get_create_dict_ex
# DIVERGES: the result is the dict's compound word, `nothing` for upstream's false (error raised); `dt` is the
# term reference that receives it, as upstream's.
"The dict `t` holds, or made of the list it holds, in the term reference `dt`; else a type error (pl-dict.c)."
function get_create_dict_ex(ld::PL_local_data{T}, t::term_t, dt::term_t)::Bool where {T}
    k, w, _ = _deref_loc(ld, -(t + 1))
    if k == DU_WORD && _is_gcompound(w)
        if is_dict_functor(ld, ld.gstack[valPtr(w)])
            ld.slots[dt + 1] = w                    # *valTermRef(dt) = *p
            return true
        end
    end

    if PL_get_dict_ex(ld, t, term_t(0), dt, DICT_GET_ALL)
        return true
    end

    return PL_type_error(ld, "dict", t)
end

# PORT: pl-dict.c dict_create as pl_dict_create3_va
# (PRED_IMPL("dict_create", 3, dict_create, 0))
"`dict_create(-Dict, +Tag, +Pairs)`: `Dict` is the dict of tag `Tag` made of the list of pairs `Pairs` (pl-dict.c)."
function pl_dict_create3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    m = PL_new_term_ref(ld)

    if PL_get_dict_ex(ld, A3, A2, m, DICT_GET_ALL)
        return PL_unify(ld, A1, m) ? FTRUE : FFALSE
    end

    return FFALSE
end

# ── put_dict/3 (part 5c) ──────────────────────────────────────────────────────────────────────────

# PORT: pl-dict.c assign_in_dict
# DIVERGES: `dp` is the position of the destination cell and `val` a value LOCATION; no TRAIL_OVERFLOW (the trail
# grows on demand), so the result is nothing.
"Store in the new dict's cell `dp` the value at `val`: a younger variable is bound to the cell (pl-dict.c)."
function assign_in_dict(ld::PL_local_data, dp::Int, val::Int)::Nothing
    k, _, q = _deref_loc(ld, val)
    if k == DU_CELL
        if dp < q
            ld.gstack[dp] = word(0)                 # setVar(*dp)
            _bind_const!(ld, q, makeRefG(dp))       # Trail(val, makeRefG(dp))
        else
            ld.gstack[dp] = makeRefG(q)
        end
    else                                            # !canBind: *dp = *val; an attributed variable: makeRefG(val)
        _dict_link!(ld, dp, val)
    end

    return nothing
end

# PORT: pl-dict.c put_dict
# DIVERGES: the merge of the two sorted runs is planned first (`plan`: which pair, from the old dict or from `nv`, comes
# next), then the cells are laid out at their exact size; upstream lays them out at gTop and sets gTop to the end
# (`gTop = out`), which the cells' allocation here cannot take back. The same pairs in the same order. The overflow
# test (`gTop+1+arity+2*size > gMax`) is `ensureGlobalSpace`, which raises the overflow: the result is then `nothing`.
# `dict` is the old dict's compound word, `nv` the position of the first VALUE cell of the `npairs` new pairs; the result is
# the new dict's compound word (the old `dict` when nothing is modified).
"The dict `dict` with the `npairs` pairs at `nv` put into it: replaced or added (pl-dict.c)."
function put_dict(
    ld::PL_local_data{T}, dict::word, npairs::Int, nv::Int
)::Union{Nothing, word} where {T}
    f = valPtr(dict)
    arity = arityFunctor(ld.functors, ld.gstack[f])
    modified = false

    @assert arity % 2 == 1

    if npairs == 0
        return dict
    end

    ensureGlobalSpace(ld, 1 + arity + 2 * npairs) || return nothing

    ip = f + 2                                      # data->arguments+1
    ip_end = ip + arity - 1
    nv_end = nv + npairs * 2
    plan = Tuple{Bool, Int, word}[]                 # (from the new pairs, value position, key word)

    while ip < ip_end && nv < nv_end
        _, i_name, _ = _deref_loc(ld, ip + 1)
        _, n_name, _ = _deref_loc(ld, nv + 1)

        if i_name == n_name
            push!(plan, (true, nv, i_name))
            if !modified && compareStandard_cells(ld, nv, ip, true) != 0
                modified = true
            end
            ip += 2
            nv += 2
        elseif i_name < n_name
            push!(plan, (false, ip, i_name))
            ip += 2
        else
            push!(plan, (true, nv, n_name))
            nv += 2
            modified = true
        end
    end

    if nv == nv_end
        if !modified
            return dict
        end
        while ip < ip_end
            _, i_name, _ = _deref_loc(ld, ip + 1)
            push!(plan, (false, ip, i_name))
            ip += 2
        end
    else
        while nv < nv_end
            _, n_name, _ = _deref_loc(ld, nv + 1)
            push!(plan, (true, nv, n_name))
            nv += 2
        end
    end

    new = allocGlobalCells!(ld, 2 + 2 * length(plan))
    out = new + 2                                   # functor, tag
    for (fresh, vpos, name) in plan
        if fresh
            assign_in_dict(ld, out, vpos)
        else
            _dict_link!(ld, out, vpos)              # *out++ = linkValI(ip)
        end
        ld.gstack[out + 1] = name
        out += 2
    end

    _dict_link!(ld, new + 1, f + 1)                 # new[1] = linkValI(&data->arguments[0])
    ld.gstack[new] = dict_functor(ld, length(plan))

    return consPtr(new, TAG_COMPOUND | STG_GLOBAL)
end

# PORT: pl-dict.c put_dict as pl_put_dict3_va
# (PRED_IMPL("put_dict", 3, put_dict, 0))
# DIVERGES: no `Mark(fli_context->mark)` / retry on `GLOBAL_OVERFLOW`: the overflow is raised by `ensureGlobalSpace`
# (the stack grows on demand, so only the limit refuses) and the predicate fails with it raised.
"`put_dict(+New, +DictIn, -DictOut)`: `DictOut` is `DictIn` with the pairs of `New` replacing or extending it (pl-dict.c)."
function pl_put_dict3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    dt = PL_new_term_refs(ld, 2)

    if get_create_dict_ex(ld, A2, dt + 0) && get_create_dict_ex(ld, A1, dt + 1)
        _, d0, _ = _deref_loc(ld, -(dt + 0 + 1))
        _, d1, _ = _deref_loc(ld, -(dt + 1 + 1))
        f2 = valPtr(d1)
        arity = arityFunctor(ld.functors, ld.gstack[f2])

        new = put_dict(ld, d0, arity ÷ 2, f2 + 2)   # &f2->arguments[1]
        if new !== nothing
            t = PL_new_term_ref(ld)
            ld.slots[t + 1] = new
            return PL_unify(ld, A3, t) ? FTRUE : FFALSE
        end
    end

    return FFALSE
end
