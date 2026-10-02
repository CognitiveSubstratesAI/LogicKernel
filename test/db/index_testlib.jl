# ORIGINAL: the test harness for the clause index — builds predicates and calls them as SWI's VM does; upstream's tests run inside swipl and need none.
# test/db/index_testlib.jl — included by the clause-index tests (test_jit.jl, test_index_swipl.jl,
# test/compile/test_head_code_swipl.jl). Not a test file itself: runtests.jl runs `test_*.jl` only.
#
# HOW A CALL IS MADE, AND WHY (pl-supervisor.c, read 2026-10-02): before a predicate's first call
# after its clause list changed, SWI replaces its S_VIRGIN supervisor (`setDefaultSupervisor`),
# which runs `reconsiderIndexes` and then `update_primary_index`. Asserting to a STATIC predicate
# resets the supervisor to S_VIRGIN (`freeCodesDefinition`); a DYNAMIC predicate's supervisor is
# set once, at its first call. The harness tracks exactly that in `IxPred.virgin`.
#
# The kernel has no unification yet, so the CALLER unifies: `ix_match` and `ix_instance` handle
# the terms these tests use — LINEAR goals and heads (no variable occurs twice) with disjoint
# variables, for which unification is structural compatibility. Every test program obeys that.
using Test, LogicKernel
const LK = LogicKernel

"A predicate under test; `virgin` is true while its supervisor is S_VIRGIN."
mutable struct IxPred{T}
    def::LK.Definition{T}
    virgin::Bool
end

"A new predicate `name/arity` (`dynamic` as by `:- dynamic`) with no clauses."
ix_pred(::Type{T}, name::Symbol, arity::Int; dynamic::Bool=false) where {T} =
    IxPred{T}(
        LK.lookupProcedure(
            T, sym_key(sym_term(T, name)), arity, dynamic ? LK.P_DYNAMIC : UInt64(0)
        ),
        true
    )

"`assertz(Head)`: compile the fact and add it at the end."
function ix_assertz!(p::IxPred{T}, head::T)::Nothing where {T}
    LK.assertDefinition!(p.def, LK.compileClause(p.def, head), LK.CL_END)
    if (p.def.flags & LK.P_DYNAMIC) == 0
        p.virgin = true                       # freeCodesDefinition(): back to S_VIRGIN
    end
    return nothing
end

"Two linear terms with disjoint variables unify iff they are structurally compatible."
function ix_match(g, h)::Bool
    (kind(g) === VAR || kind(h) === VAR) && return true
    kind(g) === kind(h) || return false
    if kind(g) === EXPR
        nchildren(g) == nchildren(h) || return false
        for i in 1:nchildren(g)
            ix_match(child(g, i), child(h, i)) || return false
        end
        return true
    end
    return compareStandard(g, h, true) == 0
end

"The common instance of two compatible linear terms."
function ix_instance(g::T, h::T)::T where {T}
    kind(g) === VAR && return h
    kind(h) === VAR && return g
    kind(g) === EXPR || return g
    return mk_expr(T, T[ix_instance(child(g, i), child(h, i)) for i in 1:nchildren(g)])
end

"""
    ix_call(p, goal) -> [(answer, det)]

Call `goal` as SWI's VM does: `firstClause!`, then `nextClause!` while a clause choice remains,
unifying each candidate. `det` is true when no clause choice is left after the answer — SWI's
`call_cleanup(G, Det=true)` for a fact.
"""
function ix_call(p::IxPred{T}, goal::T)::Vector{Tuple{T, Bool}} where {T}
    if p.virgin                               # setDefaultSupervisor()
        LK.reconsiderIndexes!(p.def)
        LK.update_primary_index!(p.def)
        p.virgin = false
    end
    gen = LK.gen_t(1)
    chp = LK.ClauseChoice{T}(nothing, LK.word(0))
    out = Tuple{T, Bool}[]
    c = LK.firstClause!(goal, gen, p.def, chp)
    while c !== nothing
        h = (c.clause::LK.Clause{T}).head
        if ix_match(goal, h)
            push!(out, (ix_instance(goal, h), chp.cref === nothing))
        end
        chp.cref === nothing && break
        c = LK.nextClause!(chp, goal, gen, p.def)
    end
    return out
end

"The same predicate, called by the oracle: every call scans every clause (no narrowing at all)."
function ix_call_unindexed(p::IxPred{T}, goal::T)::Vector{Tuple{T, Bool}} where {T}
    gen = LK.gen_t(1)
    chp = LK.ClauseChoice{T}(nothing, LK.word(0))
    out = Tuple{T, Bool}[]
    chp.cref = p.def.impl_clauses.first_clause
    while chp.cref !== nothing
        c = chp.cref::LK.ClauseRef{T}
        chp.cref = c.next
        h = (c.clause::LK.Clause{T}).head
        if ix_match(goal, h)
            push!(out, (ix_instance(goal, h), chp.cref === nothing))
        end
    end
    return out
end

"The primary index as `'\$get_predicate_attribute'(P, primary_index, N)` reports it (pl-proc.c)."
function ix_primary_index(p::IxPred)::Union{Nothing, Int}
    cl = p.def.impl_clauses
    cl.pindex_verified || LK.update_primary_index!(p.def)
    return cl.unindexed ? nothing : Int(cl.primary_index) + 1
end

# ── Prolog text for the default term type (atoms, integers, floats, compounds, `_`) ─────────────
"`t` written as `write_term(T, [quoted(true), ignore_ops(true), numbervars(true)])` writes it
after `numbervars(T, 0, _, [singletons(true)])` — every variable of a linear term prints `_`."
function ix_text(t)::String
    k = kind(t)
    k === VAR && return "_"
    if k === SYM
        n = String(sym_name(t))
        return if occursin(r"^[a-z][A-Za-z0-9_]*$", n)
            n
        else
            "'" * replace(n, "'" => "\\'") * "'"
        end
    elseif k === GND
        v = gnd_value(t)
        return v isa AbstractFloat ? repr(Float64(v)) : string(v)
    end
    return ix_text(child(t, 1)) * "(" *
           join([ix_text(child(t, i)) for i in 2:nchildren(t)], ",") *
           ")"
end
