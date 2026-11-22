# UPSTREAM: swipl-devel src/pl-index.c @ 18168e629eab
# CLASS: code
# COPYRIGHT: Copyright (c)  1985-2025, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
# allow-new-artifact: the two predicates of pl-index.c's BeginPredDefs(index) table cannot live in pl-index.jl (it loads before the local-data types)
# THE PROLOG CONNECTION OF pl-index.c: `'$candidate_indexes'/3` and `'$set_candidate_indexes'/2`, the two predicates of
# `BeginPredDefs(index)`. The index machinery itself is src/pl-index.jl (it loads before the local data, so these
# `pl_*_va` functions, which take a `PL_local_data`, are here, after pl-dict.jl: `PL_put_dict` builds the answer).

# ORIGINAL (WRAPPERS-2): the number of hints a call can ask `candidate_indexes!` for: an index has at most `MAXINDEXARG`
# arguments, so no predicate has more candidate indexes than this; a larger `Max` is the same answer (upstream
# allocates `Max` hints).
const _MAX_CANDIDATE_HINTS = 64

# PORT: pl-index.c put_args
"Make `t` hold the list of the argument numbers `args` holds, up to its first 0 (pl-index.c)."
function _put_index_args(
    ld::PL_local_data{T}, t::term_t, args::NTuple{MAX_MULTI_INDEX, iarg_t}
)::Bool where {T}
    n = 0
    while n < MAX_MULTI_INDEX && args[n + 1] != 0                   # ep-args < MAX_MULTI_INDEX && *ep
        n += 1
    end
    PL_put_nil(ld, t)
    el = PL_new_term_ref(ld)
    while n > 0
        PL_put_integer(ld, el, Int(args[n])) || return false
        PL_cons_list(ld, t, el, t) || return false
        n -= 1
    end
    PL_reset_term_refs(ld, el)
    return true
end

# PORT: pl-index.c put_hints
# DIVERGES: `speedup` is the `Float32` of the hints widened to a double (upstream: `float` to `double`); `PL_put_bool` is
# `PL_put_atom` of `true`/`false`; the keys are atoms made here (upstream's `init_dict_keys`).
"Make `t` hold `hash_info{speedup:S, ln_buckets:N, list:B, arguments:Args}` of the hints `h` (pl-index.c)."
function _put_hints(ld::PL_local_data{T}, t::term_t, h::hash_hints)::Bool where {T}
    keys = T[
        mk_sym(T, :speedup), mk_sym(T, :ln_buckets), mk_sym(T, :list), mk_sym(T, :arguments),
    ]
    values = PL_new_term_refs(ld, 4)
    rc = PL_put_float(ld, values, Float64(h.speedup)) &&
        PL_put_integer(ld, values + 1, Int(h.ln_buckets)) &&
        PL_put_atom(ld, values + 2, (h.list ? mk_sym(T, :true) : mk_sym(T, :false))) &&
        _put_index_args(ld, values + 3, h.args) &&
        PL_put_dict(ld, t, mk_sym(T, :hash_info), 4, keys, values)
    rc && PL_reset_term_refs(ld, values)
    return rc
end

# PORT: pl-index.c candidate_indexes as pl_candidate_indexes3_va
# (PRED_IMPL("$candidate_indexes", 3, candidate_indexes, PL_FA_TRANSPARENT)) — pl-index.c:3584-3623
# DIVERGES: a foreign predicate has no clause list: it has no candidate indexes (`[]`); `Max` above `_MAX_CANDIDATE_HINTS`
# asks for that many.
"`'\$candidate_indexes'(+PI, -Indexes, +Max)` (pl-index.c): the at most `Max` indexes the clauses of `PI` suggest, as `hash_info` dicts."
function pl_candidate_indexes3_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    A1, A2, A3 = PL__t0, PL__t0 + 1, PL__t0 + 2
    proc = get_procedure(gd, ld, A1, GP_RESOLVE | GP_NAMEARITY)
    proc === nothing && return FFALSE
    max = PL_get_integer_ex(ld, A3)
    max === nothing && return FFALSE
    max < 0 && return PL_domain_error(ld, "not_less_than_zero", A3) ? FTRUE : FFALSE

    def = proc.definition
    nhints = 0
    hints = hash_hints[]
    if (def.flags & P_FOREIGN) == 0
        max = min(max, _MAX_CANDIDATE_HINTS)
        hints = [hash_hints() for _ in 1:max]
        ac = def.arity < MAXINDEXARG ? def.arity : MAXINDEXARG
        ctx = index_context{T}(
            gen_t(0), def, nothing, 0, _TOP_POSITION, false, GEN_INVALID, nothing
        )
        _, nhints = candidate_indexes!(ac, def.impl_clauses, hints, max, ctx)
    end

    tail = PL_copy_term_ref(ld, A2)
    head = PL_new_term_ref(ld)
    tmp = PL_new_term_ref(ld)

    rc = true
    for i in 1:nhints
        if !_put_hints(ld, tmp, hints[i]) || !PL_unify_list(ld, tail, head, tail) ||
                !PL_unify(ld, head, tmp)
            rc = false
            break
        end
    end
    rc = rc && PL_unify_nil(ld, tail)
    return rc ? FTRUE : FFALSE
end

# PORT: pl-index.c set_candidate_indexes as pl_set_candidate_indexes2_va
# (PRED_IMPL("$set_candidate_indexes", 2, set_candidate_indexes, PL_FA_TRANSPARENT)) — pl-index.c:3503-3519
# DIVERGES: the domain error of a negative `Max` names `A2`, the argument read; a foreign predicate has no clause list, so
# nothing is set and the call succeeds; `Max` above `_MAX_CANDIDATE_HINTS` asks for that many.
"`'\$set_candidate_indexes'(+PI, +Max)` (pl-index.c): set the at most `Max` candidate indexes of `PI`, not yet realised."
function pl_set_candidate_indexes2_va(
    ld::PL_local_data{T}, PL__t0::term_t, PL__ac::Int, PL__ctx::control_t{T}
)::foreign_t where {T}
    gd = _query_gd(ld)
    A1, A2 = PL__t0, PL__t0 + 1
    proc = get_procedure(gd, ld, A1, GP_RESOLVE | GP_NAMEARITY)
    proc === nothing && return FFALSE
    def = proc.definition
    max = PL_get_integer_ex(ld, A2)
    max === nothing && return FFALSE
    max < 0 && return PL_domain_error(ld, "not_less_than_zero", A2) ? FTRUE : FFALSE

    (def.flags & P_FOREIGN) != 0 && return FTRUE
    rc = set_candidate_indexes!(def, def.impl_clauses, min(max, _MAX_CANDIDATE_HINTS), true)
    return rc ? FTRUE : FFALSE
end

# PORT: pl-index.c BeginPredDefs as PL_predicates_from_index
# (`META` is `PL_FA_TRANSPARENT`, `PRED_DEF` ors in `PL_FA_VARARGS`)
"pl-index.c's registration table (`BeginPredDefs(index)`)."
const PL_predicates_from_index = (
    PL_extension(
        "\$candidate_indexes", 3, pl_candidate_indexes3_va, PL_FA_TRANSPARENT | PL_FA_VARARGS
    ),
    PL_extension(
        "\$set_candidate_indexes", 2, pl_set_candidate_indexes2_va,
        PL_FA_TRANSPARENT | PL_FA_VARARGS
    )
)
