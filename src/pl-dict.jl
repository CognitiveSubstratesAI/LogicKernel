# UPSTREAM: swipl-devel src/pl-dict.c @ cbf4e1896275
# UPSTREAM: swipl-devel src/pl-dict.h @ cbf4e1896275
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

# ORIGINAL (BOOTPRED): pl-atom.ih `ATOM_dict` (generated from src/ATOMS): the reserved atom `dict` (src/pl-ressymbol.jl retypes it).
"The atom word of the reserved symbol `dict` (pl-atom.ih `ATOM_dict`): the same in every database."
const ATOM_dict = builtin_atom("dict")

# PORT: pl-dict.c dict_functor
# DIVERGES: no `GD->dict.dict_functors` cache for the small arities: the table is asked every time. The reserved
# symbol `dict` is recorded in the database's symbol store (`_atom_word!`) so a reader of the functor's name
# (the compiler's argvar placeholder, `_atom_value`) finds its interface symbol; the word is `ATOM_dict` either way.
"The functor word of a dict with `pairs` key-value pairs: `dict`/(2*pairs+1) (pl-dict.c)."
function dict_functor(ld::PL_local_data{T}, pairs::Int)::word where {T}
    _atom_word!(ld, mk_reserved_symbol(T, :dict))
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
function get_dict_ex(
    ld::PL_local_data{T}, t::term_t, ex::Bool
)::Union{Nothing, word} where {T}
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

# PORT: pl-dict.c DICT_GET_ALL
"`PL_get_dict_ex`' `flags`: all forms of a key-value pair are read (pl-dict.c)."
const DICT_GET_ALL = Int(0xff)

# PORT: pl-dict.c DICT_GET_PAIRS
"`PL_get_dict_ex`' `flags`: `Key-Value` is read (pl-dict.c)."
const DICT_GET_PAIRS = Int(0x01)

# PORT: pl-dict.c DICT_GET_EQUALS
"`PL_get_dict_ex`' `flags`: `Key=Value` is read (pl-dict.c)."
const DICT_GET_EQUALS = Int(0x02)

# PORT: pl-dict.c DICT_GET_COLON
"`PL_get_dict_ex`' `flags`: `Key:Value` is read (pl-dict.c)."
const DICT_GET_COLON = Int(0x04)

# PORT: pl-dict.c DICT_GET_TERM
"`PL_get_dict_ex`' `flags`: `Key(Value)` is read (pl-dict.c)."
const DICT_GET_TERM = Int(0x08)

# ORIGINAL (BOOTPRED): the term reference `ex` raised as `error(duplicate_key(Key), _)`: pl-error.c's `ERR_DUPLICATE_KEY`
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

# ORIGINAL (BOOTPRED): pl-inline.h `*dp = linkValI(val)` for a value LOCATION `loc` (a global position or a slot, `_deref_loc`'s):
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

# PORT: pl-dict.c dict_order
# (`compare_dict_entry`, the comparison `sort_r` is given, is the order `sortperm` has on the key words.)
# DIVERGES: the pairs are sorted by their key WORDS (`SCALAR_TO_CMP` on the dereferenced key cells) with Julia's
# `sortperm` on the keys read out, the cells written back in the new order (upstream: `sort_r` over the cells in
# place); `dict` is the position of the functor cell; the result is `(status, dupl)` as `dict_ordered`'s.
"Sort the pairs of the dict at `dict` by key and check them: `(status, duplicate key word)` (pl-dict.c)."
function dict_order(
    ld::PL_local_data{T}, dict::Int
)::Tuple{_PL_dict_status_t, word} where {T}
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

# ── select_dict/3, get_dict/3 (part 5d) ───────────────────────────────────────────────────────────

# ORIGINAL (BOOTPRED): pl-atom.ih `ATOM_dyndict` (generated from src/ATOMS): the tag of a dict made from others (select_dict/3's rest).
"The atom word of `dyndict` (pl-atom.ih `ATOM_dyndict`): the same in every database."
const ATOM_dyndict = builtin_atom("dyndict")

# ORIGINAL (BOOTPRED): pl-dict.c `Word` pointer arguments as LOCATIONS: `_dict_unify_key` is `PL_unify_atomic(t, w)` for a key WORD
# `w` (an atom or a small integer: `PL_unify_atomic` here takes an atomic term, not a word). A variable is bound to it;
# anything else is equal to it only as the same word (an atom's word is unique, a small integer is tagged in place).
"Unify the term reference `t` with the dict key word `w` (pl-fli.c `PL_unify_atomic` on a word)."
function _dict_unify_key(ld::PL_local_data, t::term_t, w::word)::Bool
    k, c, q = _deref_loc(ld, -(t + 1))
    if k == DU_CELL || k == DU_ATTVAR
        bindConst(ld, q, w)
        return true
    end

    return c == w
end

# PORT: pl-dict.c unify_tags
# DIVERGES: `t1` and `t2` are locations; no `flags` (`unify_ptrs_cells` takes none).
"Unify two dict tags; true if either is `dyndict` (pl-dict.c)."
function unify_tags(ld::PL_local_data, t1::Int, t2::Int)::Bool
    _, w1, _ = _deref_loc(ld, t1)
    _, w2, _ = _deref_loc(ld, t2)

    if w1 == ATOM_dyndict || w2 == ATOM_dyndict
        return true
    end

    return unify_ptrs_cells(ld, t1, t2)
end

# PORT: pl-dict.c select_dict
# DIVERGES: the result is the new dict's compound word, `word(0)` for upstream's false (also when the global overflow was
# raised: `ensureGlobalSpace`, where upstream returns `GLOBAL_OVERFLOW` for its caller to retry); `keep` is a `Vector{Bool}`,
# not a `bit_vector` on a 256-int buffer; the cells are laid out after the count is known (`allocGlobalCells!`).
"The rest of the dict `from` after the dict `del` was unified with the keys it shares: a `dyndict` dict, or `word(0)` (pl-dict.c)."
function select_dict(ld::PL_local_data{T}, del::word, from::word)::word where {T}
    dd = valPtr(del)
    fd = valPtr(from)
    din = dd + 1                                    # dd->arguments
    fin = fd + 1
    dend = din + arityFunctor(ld.functors, ld.gstack[dd])
    fend = fin + arityFunctor(ld.functors, ld.gstack[fd])
    keep = nothing

    # unify the tags
    unify_tags(ld, din, fin) || return word(0)

    # advance to first v+k entry
    din += 1
    fin += 1

    i = 0
    while din < dend && fin < fend
        _, d, _ = _deref_loc(ld, din + 1)
        _, f, _ = _deref_loc(ld, fin + 1)

        if d == f                                   # same keys
            unify_ptrs_cells(ld, din, fin) || return word(0)
            din += 2
        elseif d < f
            return word(0)
        else
            if keep === nothing
                keep = fill(false, arityFunctor(ld.functors, ld.gstack[fd]) ÷ 2)
            end
            keep[i + 1] = true
        end
        i += 1
        fin += 2
    end

    if din == dend                                  # unification succeeded
        nsize = (keep === nothing ? 0 : count(keep)) + (fend - fin) ÷ 2

        ensureGlobalSpace(ld, nsize * 2 + 2) || return word(0)
        out = allocGlobalCells!(ld, nsize * 2 + 2)
        new_dict = consPtr(out, TAG_COMPOUND | STG_GLOBAL)
        ld.gstack[out] = dict_functor(ld, nsize)
        _atom_word!(ld, mk_sym(T, Symbol("#")))                # records the symbol of `dyndict` (text `#`) for readers
        ld.gstack[out + 1] = ATOM_dyndict
        out += 2

        fe = fin
        fin = fd + 2                                # fd->arguments+1
        i = 0
        while fin < fend
            if fin >= fe || (keep !== nothing && keep[i + 1])
                _, f, _ = _deref_loc(ld, fin + 1)
                _dict_link!(ld, out, fin)           # *out++ = linkValI(fin)
                ld.gstack[out + 1] = f              # *out++ = *f
                out += 2
            end
            i += 1
            fin += 2
        end

        return new_dict
    end

    return word(0)
end

# PORT: pl-dict.c select_dict as pl_select_dict3_va
# (PRED_IMPL("select_dict", 3, select_dict, 0))
# DIVERGES: no `Mark(fli_context->mark)` and no retry after a global overflow (raised by `ensureGlobalSpace`).
"`select_dict(+Select, +From, -Rest)`: `Select` unifies with the pairs of `From` it names; `Rest` is the others (pl-dict.c)."
function pl_select_dict3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    dt = PL_new_term_refs(ld, 2)

    if get_create_dict_ex(ld, A1, dt + 0) && get_create_dict_ex(ld, A2, dt + 1)
        _, d0, _ = _deref_loc(ld, -(dt + 0 + 1))
        _, d1, _ = _deref_loc(ld, -(dt + 1 + 1))
        r = select_dict(ld, d0, d1)

        if r != word(0)
            t = PL_new_term_ref(ld)
            ld.slots[t + 1] = r
            return PL_unify(ld, A3, t) ? FTRUE : FFALSE
        end
    end

    return FFALSE
end

# PORT: pl-dict.c pl_get_dict
# DIVERGES: `i` is the 0-based index into the ARGUMENTS as upstream's (`f->arguments[i]` is position `f + 1 + i`);
# `exception_term` is `PL_exception(ld, 0) != 0`. `ex` as upstream's: `get_dict/3` is `ex = false`, which raises
# `type_error(dict, …)` for a non-dict (`get_dict_ex(A2, &dict, !ex)`); `$get_dict_ex/3` (`ex = true`) is `pl_get_dict_ex3_va`.
# With a key bound the lookup is one binary search (`dict_lookup_ptr`); with it unbound the
# pairs are enumerated in the dict's (kernel-word) order, `ForeignRedoInt(i)` carrying the index.
"The body of `get_dict/3` (and `$get_dict_ex/3`): `Value` is the value of `Key` in the dict, or on backtracking every pair (pl-dict.c)."
function pl_get_dict(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, ex::Bool, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    ctl = PL_foreign_control(PL__ctx)
    dict = word(0)
    i = 0

    if ctl == FRG_FIRST_CALL
        d = get_dict_ex(ld, A2, !ex)
        d === nothing && return FFALSE
        dict = d

        k, np, _ = _deref_loc(ld, -(A1 + 1))
        if is_dict_key(np)
            r = dict_lookup_ptr(ld, dict, np)
            if r !== nothing
                return unify_ptrs_cells(ld, r[1], -(A3 + 1)) ? FTRUE : FFALSE
            end

            if ex
                PL_existence_error3(ld, mk_sym(T, :key), A1, A2)
            end
            return FFALSE
        end
        if k == DU_CELL || k == DU_ATTVAR           # canBind(*np)
            i = 1
        else
            if !ex
                PL_type_error(ld, "dict-key", A1)
            end
            return FFALSE
        end
    elseif ctl == FRG_REDO
        i = PL_foreign_context(PL__ctx) + 2
        _, dict, _ = _deref_loc(ld, -(A2 + 1))
    else
        return FTRUE
    end

    # search:
    f = valPtr(dict)
    arity = arityFunctor(ld.functors, ld.gstack[f])

    fid = PL_open_foreign_frame(ld)
    if fid != 0
        while i < arity
            _, np, _ = _deref_loc(ld, f + 1 + i + 1)        # deRef2(&f->arguments[i+1], np)    TBD: check type
            if unify_ptrs_cells(ld, f + 1 + i, -(A3 + 1)) && _dict_unify_key(ld, A1, np)
                PL_close_foreign_frame(ld, fid)

                if i + 2 < arity
                    return PL_retry(i)                      # ForeignRedoInt(i)
                else
                    return FTRUE
                end
            elseif PL_exception(ld, 0) != 0
                PL_close_foreign_frame(ld, fid)
                return FFALSE
            end
            PL_rewind_foreign_frame(ld, fid)
            i += 2
        end
        PL_close_foreign_frame(ld, fid)
    end

    return FFALSE
end

# PORT: pl-dict.c get_dict as pl_get_dict3_va
# (PRED_IMPL("get_dict", 3, get_dict, PL_FA_NONDETERMINISTIC))
"`get_dict(?Key, +Dict, ?Value)`: `Key` is associated with `Value` in `Dict`; with `Key` unbound, every pair (pl-dict.c)."
function pl_get_dict3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return pl_get_dict(ld, PL__t0, PL__ac, false, PL__ctx)
end

# PORT: pl-dict.c get_dict_ex as pl_get_dict_ex3_va
# (PRED_IMPL("get_dict_ex", 3, get_dict_ex, PL_FA_NONDETERMINISTIC); registered as `$get_dict_ex`, pl-dict.c's table)
# DIVERGES: the predicate's name in the registration table is `$get_dict_ex`; the PRED_IMPL name is `get_dict_ex`.
"`\$get_dict_ex(?Key, +Dict, ?Value)`: `get_dict/3` that fails for a missing key and raises for a non-dict (pl-dict.c)."
function pl_get_dict_ex3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return pl_get_dict(ld, PL__t0, PL__ac, true, PL__ctx)
end

# PORT: pl-dict.c get_dict as pl_get_dict5_va
# (PRED_IMPL("get_dict", 5, get_dict, 0))
# DIVERGES: `av` of upstream (two term references, the new value and the key, handed to `put_dict` as cells in a row) is
# two global cells here (`put_dict` reads global positions): the value cell links `A5` (`linkValI`), the key cell holds the
# key word. No `makeMoreStackSpace` retry loop: the overflow is raised by `ensureGlobalSpace` and the predicate fails.
"`get_dict(+Key, +Dict, -Val, -NewVal, -NewDict)`: `Val` is `Key`'s value in `Dict` and `NewDict` has `NewVal` there (pl-dict.c)."
function pl_get_dict5_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3, A4, A5 = PL__t0, PL__t0 + 1, PL__t0 + 2, PL__t0 + 3, PL__t0 + 4
    dt = PL_new_term_refs(ld, 1)

    key = get_name_ex(ld, A1)
    key === nothing && return FFALSE
    get_create_dict_ex(ld, A2, dt) || return FFALSE
    _, dict, _ = _deref_loc(ld, -(dt + 1))
    r = dict_lookup_ptr(ld, dict, key)
    r === nothing && return FFALSE
    unify_ptrs_cells(ld, r[1], -(A3 + 1)) || return FFALSE

    av = allocGlobalCells!(ld, 2)
    _dict_link!(ld, av, -(A5 + 1))                  # PL_put_term(av+0, A5)
    ld.gstack[av + 1] = key                         # *valTermRef(av+1) = key

    new = put_dict(ld, dict, 1, av)
    new === nothing && return FFALSE
    t = PL_new_term_ref(ld)
    ld.slots[t + 1] = new
    return PL_unify(ld, A4, t) ? FTRUE : FFALSE
end

# PORT: pl-dict.c put_dict4
# DIVERGES: as `pl_get_dict5_va`: the pair (`av`, `av+1` upstream) is two global cells, the value cell links `value`; no
# `Mark`/`Undo` retry (the overflow is raised by `ensureGlobalSpace`).
"`put_dict(+Key, +Dict0, +Value, -Dict)`: `Dict` is `Dict0` with `Key` added or replaced by `Value` (pl-dict.c)."
function put_dict4(
    ld::PL_local_data{T}, key::term_t, dict::term_t, value::term_t, newdict::term_t
)::foreign_t where {T}
    dt = PL_new_term_refs(ld, 1)

    if get_create_dict_ex(ld, dict, dt)
        k = get_name_ex(ld, key)
        k === nothing && return FFALSE
        av = allocGlobalCells!(ld, 2)
        _dict_link!(ld, av, -(value + 1))           # PL_put_term(av, value)
        ld.gstack[av + 1] = k

        _, d0, _ = _deref_loc(ld, -(dt + 1))
        new = put_dict(ld, d0, 1, av)
        if new !== nothing
            t = PL_new_term_ref(ld)
            ld.slots[t + 1] = new
            return PL_unify(ld, newdict, t) ? FTRUE : FFALSE
        end
    end

    return FFALSE
end

# PORT: pl-dict.c put_dict as pl_put_dict4_va
# (PRED_IMPL("put_dict", 4, put_dict, 0))
"`put_dict(+Key, +DictIn, +Value, -DictOut)`: `DictOut` is `DictIn` with `Key` set to `Value` (pl-dict.c)."
function pl_put_dict4_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    return put_dict4(ld, PL__t0, PL__t0 + 1, PL__t0 + 2, PL__t0 + 3)
end

# PORT: SWI-Prolog.h PL_FOR_DICT_SORTED
"`PL_for_dict`' flag: the pairs are visited in the standard order of terms of their keys (SWI-Prolog.h)."
const PL_FOR_DICT_SORTED = Int(0x1)

# PORT: pl-dict.c pl_dict_pairs
"The number of key-value pairs of the dict the term reference `dict` holds (pl-dict.c)."
function pl_dict_pairs(ld::PL_local_data, dict::term_t)::Int
    _, w, _ = _deref_loc(ld, -(dict + 1))
    return arityFunctor(ld.functors, ld.gstack[valPtr(w)]) ÷ 2
end

# PORT: pl-dict.c pl_dict_sort_indexes
# DIVERGES: the result is the vector of the pair indexes (0-based) in the standard order of their keys, where upstream
# fills a caller buffer through `sort_r(…, cmp_dict_index, …)`; the keys are atoms or small integers and the standard
# order (numbers before atoms, integers by value, atoms by `compareAtoms`) is `cmp_dict_index`'s, so the comparison is
# `compareStandard_cells` on the key cells.
"The pair indexes of the dict `dict` holds, in the standard order of terms of the keys (pl-dict.c)."
function pl_dict_sort_indexes(ld::PL_local_data, dict::term_t, pairs::Int)::Vector{Int}
    _, w, _ = _deref_loc(ld, -(dict + 1))
    f = valPtr(w)
    indexes = collect(0:(pairs - 1))
    sort!(indexes; lt = (a, b) -> compareStandard_cells(ld, f + 3 + 2 * a, f + 3 + 2 * b, false) < 0)

    return indexes
end

# PORT: pl-dict.c pl_dict_pair
# DIVERGES: `indexes` is `nothing` for upstream's NULL. The key is put in `av+0`, the value in `av+1` as `linkValI`
# reads the cells (`_slot_from_cell!`).
"Put the key and the value of the `i`-th pair (0-based, in the order `indexes` gives) of `dict` in `av+0`, `av+1` (pl-dict.c)."
function pl_dict_pair(
    ld::PL_local_data, dict::term_t, indexes::Union{Nothing, Vector{Int}}, i::Int, av::term_t
)::Nothing
    _, w, _ = _deref_loc(ld, -(dict + 1))
    f = valPtr(w)
    in_ = (indexes === nothing ? i : indexes[i + 1]) * 2 + 1
    _slot_from_cell!(ld, av + 0 + 1, f + 1 + in_ + 1)       # *valTermRef(av+0) = linkValI(&f->arguments[in+1])
    _slot_from_cell!(ld, av + 1 + 1, f + 1 + in_)           # *valTermRef(av+1) = linkValI(&f->arguments[in])

    return nothing
end

# PORT: pl-dict.c pl_for_dict
# DIVERGES: `func(key, value, last)` is a Julia function returning 0 to go on (upstream's `func` with its `closure`; the
# closure is what `func` captures). `PL_for_dict`'s `func(key, value, closure)` is `pl_for_dict` with a `func` of two
# arguments: `(k, v, last) -> func(k, v)`.
"Run `func(key, value, last)` on each pair of `dict` until it returns non-zero, that value (pl-dict.c)."
function pl_for_dict(ld::PL_local_data, dict::term_t, func, flags::Int)::Int
    av = PL_new_term_refs(ld, 2)
    pairs = pl_dict_pairs(ld, dict)
    indexes = (flags & PL_FOR_DICT_SORTED) != 0 ? pl_dict_sort_indexes(ld, dict, pairs) : nothing
    rc = 0

    i = 0
    while i < pairs
        pl_dict_pair(ld, dict, indexes, i, av)
        i += 1
        rc = func(av + 0, av + 1, i == pairs)
        rc != 0 && break
    end

    return rc
end

# PORT: pl-dict.c put_pair
# DIVERGES: the closure's `head`, `tail`, `tmp` term references are captured by `pl_dict_pairs3_va`'s function.
"Append `key-value` to the list under construction: `tmp` the pair, `tail` the open tail, `head` its new head (pl-dict.c)."
function put_pair(
    ld::PL_local_data{T}, key::term_t, value::term_t, head::term_t, tail::term_t, tmp::term_t
)::Int where {T}
    if PL_cons_functor(ld, tmp, _err_functor(ld, :-, 2), key, value) &&
       PL_unify_list_ex(ld, tail, head, tail) &&
       PL_unify(ld, head, tmp)
        return 0
    end

    return -1
end

# PORT: pl-dict.c dict_pairs as pl_dict_pairs3_va
# (PRED_IMPL("dict_pairs", 3, dict_pairs, 0))
"`dict_pairs(?Dict, ?Tag, ?Pairs)`: `Pairs` are the `Key-Value` pairs of `Dict` in standard order of the keys; also creates (pl-dict.c)."
function pl_dict_pairs3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2

    if !PL_is_variable(ld, A1)
        dict = PL_new_term_ref(ld)

        if get_create_dict_ex(ld, A1, dict)
            tail = PL_copy_term_ref(ld, A3)
            head = PL_new_term_refs(ld, 2)
            tmp = head + 1

            if _PL_get_arg(ld, 1, dict, tmp) &&
               PL_unify(ld, tmp, A2) &&
               pl_for_dict(ld, dict, (k, v, last) -> put_pair(ld, k, v, head, tail, tmp), PL_FOR_DICT_SORTED) == 0
                return PL_unify_nil_ex(ld, tail) ? FTRUE : FFALSE
            end

            return FFALSE
        end
    else
        m = PL_new_term_ref(ld)

        if PL_get_dict_ex(ld, A3, A2, m, DICT_GET_PAIRS)
            return PL_unify(ld, A1, m) ? FTRUE : FFALSE
        end
    end

    return FFALSE
end

# PORT: pl-dict.c del_dict
# DIVERGES: the result is the new dict's compound word, `nothing` for upstream's `GLOBAL_OVERFLOW` (the overflow raised by
# `ensureGlobalSpace`); the pairs kept are planned first and laid out at their exact size (as `put_dict`). `dict` is the dict's
# compound word, `key` a key word.
"The dict `dict` without the pair of key `key`, tag and the other pairs kept (pl-dict.c)."
function del_dict(ld::PL_local_data{T}, dict::word, key::word)::Union{Nothing, word} where {T}
    f = valPtr(dict)
    arity = arityFunctor(ld.functors, ld.gstack[f])

    @assert arity % 2 == 1

    ensureGlobalSpace(ld, 1 + arity - 2) || return nothing

    keep = Tuple{Int, word}[]                       # (value position, key word)
    in_ = f + 2                                     # data->arguments+1
    in_end = in_ + arity - 1
    while in_ < in_end
        _, i_name, _ = _deref_loc(ld, in_ + 1)
        if i_name != key
            push!(keep, (in_, i_name))
        end
        in_ += 2
    end

    new = allocGlobalCells!(ld, 2 + 2 * length(keep))
    out = new + 2                                   # functor, tag
    for (vpos, name) in keep
        _dict_link!(ld, out, vpos)                  # *out++ = linkValI(in)
        ld.gstack[out + 1] = name
        out += 2
    end

    _dict_link!(ld, new + 1, f + 1)                 # new[1] = linkValI(&data->arguments[0])  tag
    ld.gstack[new] = dict_functor(ld, length(keep)) # arity

    return consPtr(new, TAG_COMPOUND | STG_GLOBAL)
end

# PORT: pl-dict.c del_dict as pl_del_dict4_va
# (PRED_IMPL("del_dict", 4, del_dict, 0))
# DIVERGES: no foreign frame to rewind and no retry after a global overflow (raised by `ensureGlobalSpace`).
"`del_dict(+Key, +DictIn, ?Value, -DictOut)`: `Key-Value` is in `DictIn`, `DictOut` has all its keys but `Key` (pl-dict.c)."
function pl_del_dict4_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    A1, A2, A3, A4 = PL__t0, PL__t0 + 1, PL__t0 + 2, PL__t0 + 3
    mt = PL_new_term_ref(ld)

    if get_create_dict_ex(ld, A2, mt)
        key = get_name_ex(ld, A1)
        key === nothing && return FFALSE
        _, d, _ = _deref_loc(ld, -(mt + 1))
        r = dict_lookup_ptr(ld, d, key)
        if r !== nothing && unify_ptrs_cells(ld, r[1], -(A3 + 1))
            _, d, _ = _deref_loc(ld, -(mt + 1))
            new = del_dict(ld, d, key)
            if new !== nothing
                t = PL_new_term_ref(ld)
                ld.slots[t + 1] = new
                return PL_unify(ld, A4, t) ? FTRUE : FFALSE
            end
        end
    end

    return FFALSE
end

# PORT: pl-dict.c partial_unify_dict
# DIVERGES: `dict1`, `dict2` are the dicts' compound words; the result is a Bool (upstream's `boolex_t` also carries the
# overflows, which `unify_ptrs_cells` raises).
"Unify all common elements of the two dicts, tags included (pl-dict.c)."
function partial_unify_dict(ld::PL_local_data, dict1::word, dict2::word)::Bool
    d1 = valPtr(dict1)
    d2 = valPtr(dict2)
    in1 = d1 + 1                                    # d1->arguments
    in2 = d2 + 1
    end1 = in1 + arityFunctor(ld.functors, ld.gstack[d1])
    end2 = in2 + arityFunctor(ld.functors, ld.gstack[d2])

    unify_tags(ld, in1, in2) || return false        # unify the tags

    in1 += 1                                        # advance to first v+k entry
    in2 += 1

    while in1 < end1 && in2 < end2
        _, n1, _ = _deref_loc(ld, in1 + 1)
        _, n2, _ = _deref_loc(ld, in2 + 1)
        if n1 == n2
            unify_ptrs_cells(ld, in1, in2) || return false
            in1 += 2
            in2 += 2
        elseif n1 < n2
            in1 += 2
        else
            in2 += 2
        end
    end

    return true
end

# PORT: pl-dict.c unify_left_dict
# DIVERGES: as `partial_unify_dict`.
"Demand `del` to be a sub-dict of `from`, unifying the values of the keys they share (pl-dict.c)."
function unify_left_dict(ld::PL_local_data, del::word, from::word)::Bool
    dd = valPtr(del)
    fd = valPtr(from)
    din = dd + 1                                    # dd->arguments
    fin = fd + 1
    dend = din + arityFunctor(ld.functors, ld.gstack[dd])
    fend = fin + arityFunctor(ld.functors, ld.gstack[fd])

    unify_tags(ld, din, fin) || return false        # unify the tags

    din += 1                                        # advance to first v+k entry
    fin += 1

    while din < dend && fin < fend
        _, d, _ = _deref_loc(ld, din + 1)
        _, f, _ = _deref_loc(ld, fin + 1)

        if d == f                                   # same keys
            unify_ptrs_cells(ld, din, fin) || return false
            din += 2
            fin += 2
        elseif d < f
            return false
        else
            fin += 2
        end
    end

    return din == dend
end

# PORT: pl-dict.c unify_left_dict as pl_unify_left_dict2_va
# (PRED_IMPL(":<", 2, unify_left_dict, 0))
# DIVERGES: no `Mark`/`Undo` retry after an overflow (raised by `ensureGlobalSpace`, failing the predicate).
"`Select :< From`: every key of `Select` is in `From` and the values unify (pl-dict.c)."
function pl_unify_left_dict2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    dt = PL_new_term_refs(ld, 2)

    if get_create_dict_ex(ld, PL__t0, dt + 0) && get_create_dict_ex(ld, PL__t0 + 1, dt + 1)
        _, d0, _ = _deref_loc(ld, -(dt + 0 + 1))
        _, d1, _ = _deref_loc(ld, -(dt + 1 + 1))
        return unify_left_dict(ld, d0, d1) ? FTRUE : FFALSE
    end

    return FFALSE
end

# PORT: pl-dict.c punify_dict as pl_punify_dict2_va
# (PRED_IMPL(">:<", 2, punify_dict, 0))
"`Dict1 >:< Dict2`: the values of the keys the two dicts share unify (pl-dict.c)."
function pl_punify_dict2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    dt = PL_new_term_refs(ld, 2)

    if get_create_dict_ex(ld, PL__t0, dt + 0) && get_create_dict_ex(ld, PL__t0 + 1, dt + 1)
        _, d0, _ = _deref_loc(ld, -(dt + 0 + 1))
        _, d1, _ = _deref_loc(ld, -(dt + 1 + 1))
        return partial_unify_dict(ld, d0, d1) ? FTRUE : FFALSE
    end

    return FFALSE
end

# PORT: pl-dict.c BeginPredDefs as PL_predicates_from_dict
# DIVERGES: the ported entries, in upstream's order (upstream's table also has `dict_pairs/3`, `dict_same_keys/2`,
# `put_dict/4`, `b_set_dict/3`, `nb_set_dict/3`, `nb_link_dict/3`, `$get_dict_ex/3`, `del_dict/4`, `get_dict/5`, `:</2`,
# `>:</2` and `$get_dict_kv/4,6,8`).
"pl-dict.c's registration table (`BeginPredDefs(dict)`): the ported entries."
const PL_predicates_from_dict = (
    PL_extension("is_dict", 1, pl_is_dict1_va, PL_FA_VARARGS),
    PL_extension("is_dict", 2, pl_is_dict2_va, PL_FA_VARARGS),
    PL_extension("dict_create", 3, pl_dict_create3_va, PL_FA_VARARGS),
    PL_extension("put_dict", 3, pl_put_dict3_va, PL_FA_VARARGS),
    PL_extension("get_dict", 3, pl_get_dict3_va, PL_FA_NONDETERMINISTIC | PL_FA_VARARGS),
    PL_extension("select_dict", 3, pl_select_dict3_va, PL_FA_VARARGS),
    PL_extension("\$get_dict_ex", 3, pl_get_dict_ex3_va, PL_FA_NONDETERMINISTIC | PL_FA_VARARGS),
    PL_extension("get_dict", 5, pl_get_dict5_va, PL_FA_VARARGS),
    PL_extension("put_dict", 4, pl_put_dict4_va, PL_FA_VARARGS),
    PL_extension("dict_pairs", 3, pl_dict_pairs3_va, PL_FA_VARARGS),
    PL_extension("del_dict", 4, pl_del_dict4_va, PL_FA_VARARGS),
    PL_extension(":<", 2, pl_unify_left_dict2_va, PL_FA_VARARGS),
    PL_extension(">:<", 2, pl_punify_dict2_va, PL_FA_VARARGS)
)
