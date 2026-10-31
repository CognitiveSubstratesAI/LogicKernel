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
