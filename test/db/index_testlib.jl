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
# Unification is the KERNEL's (src/pl-prims.jl, since 2026-10-03): a candidate clause is unified with
# the goal by `decompileHead!` (a fresh copy of its head) under the database's local data, the answer
# is copied out with `resolve_term`, and the bindings are undone — what retract/1, clause/2 and a
# call do. (Until then the harness carried its own unifier.)
using Test, LogicKernel
const LK = LogicKernel

"A database: the global and local data its predicates live in (src/pl-global.jl)."
struct IxDB{T}
    gd::LK.PL_global_data{T}
    ld::LK.PL_local_data{T}
end
IxDB{T}() where {T} = IxDB{T}(LK.PL_global_data{T}(), LK.PL_local_data{T}())

"A predicate under test, in database `db`; `virgin` is true while its supervisor is S_VIRGIN."
mutable struct IxPred{T}
    db::IxDB{T}
    def::LK.Definition{T}
    virgin::Bool
end

"A new predicate `name/arity` (`dynamic` as by `:- dynamic`) with no clauses, in `db`."
ix_pred(
    ::Type{T}, name::Symbol, arity::Int; dynamic::Bool=false, db::IxDB{T}=IxDB{T}()
) where {T} =
    IxPred{T}(
        db,
        LK.lookupProcedure(
            T, sym_key(sym_term(T, name)), arity, dynamic ? LK.P_DYNAMIC : UInt64(0)
        ),
        true
    )

"`assertz(Head)`: compile the fact and add it at the end."
function ix_assertz!(p::IxPred{T}, head::T)::Nothing where {T}
    LK.assertDefinition!(p.db.gd, p.def, LK.compileClause(p.def, head), LK.CL_END)
    if (p.def.flags & LK.P_DYNAMIC) == 0
        p.virgin = true                       # freeCodesDefinition(): back to S_VIRGIN
    end
    return nothing
end

"""
The answer of unifying `goal` with clause `cl`'s head — the goal with the bindings applied — or
`nothing` when they do not unify. Leaves no binding behind.
"""
function ix_answer(
    ld::LK.PL_local_data{T}, goal::T, cl::LK.Clause{T}
)::Union{Nothing, T} where {T}
    m = LK.Mark(ld)
    try
        return LK.decompileHead!(ld, cl, goal) ? LK.resolve_term(ld, goal) : nothing
    finally
        LK.Undo!(ld, m)
    end
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
    # the call's frame: it runs in the current generation, and clause GC must see it — the kernel
    # has no frames, so the call references the predicate as a foreign enumeration does
    dref = LK.pushPredicateAccessObj!(p.db.ld, p.db.gd, p.def)
    gen = dref.generation
    chp = LK.ClauseChoice{T}(nothing, LK.word(0))
    out = Tuple{T, Bool}[]
    c = LK.firstClause!(p.db.ld, goal, gen, p.def, chp)
    while c !== nothing
        a = ix_answer(p.db.ld, goal, c.clause::LK.Clause{T})
        if a !== nothing
            push!(out, (a, chp.cref === nothing))
        end
        chp.cref === nothing && break
        c = LK.nextClause!(p.db.ld, chp, goal, gen, p.def)
    end
    LK.popPredicateAccess!(p.db.ld, p.def)
    return out
end

"The same predicate, called by the oracle: every call scans every clause (no narrowing at all)."
function ix_call_unindexed(p::IxPred{T}, goal::T)::Vector{Tuple{T, Bool}} where {T}
    gen = LK.global_generation(p.db.gd)
    out = Tuple{T, Bool}[]
    c = p.def.impl_clauses.first_clause
    while c !== nothing
        cl = c.clause::LK.Clause{T}
        if LK.visibleClause(cl, gen)
            a = ix_answer(p.db.ld, goal, cl)
            a === nothing || push!(out, (a, c.next === nothing))
        end
        c = c.next
    end
    return out
end

"""
    ix_retract!(p, goal; after = (instance -> true)) -> [instance]

`retract(Goal)`, backtracking into it while `after(instance)` — the goals after it — returns true;
the instances of the retracted clauses, in order.
"""
function ix_retract!(p::IxPred{T}, goal::T; after=(_ -> true))::Vector{T} where {T}
    out = T[]
    LK.pl_retract!(
        p.db.gd, p.db.ld, p.def, goal,
        cl -> (push!(out, LK.resolve_term(p.db.ld, goal)); after(out[end]))
    )
    return out
end

"`retractall(Goal)`."
ix_retractall!(p::IxPred{T}, goal::T) where {T} =
    LK.pl_retractall!(p.db.gd, p.db.ld, p.def, goal)

"""
    ix_clause(p, goal; after = (instance -> true)) -> [instance]

`clause(Goal, true)`, backtracking while `after(instance)` returns true; the instances, in order.
"""
function ix_clause(p::IxPred{T}, goal::T; after=(_ -> true))::Vector{T} where {T}
    out = T[]
    LK.pl_clause!(
        p.db.gd, p.db.ld, p.def, goal,
        cl -> (push!(out, LK.resolve_term(p.db.ld, goal)); after(out[end]))
    )
    return out
end

"`garbage_collect_clauses`."
ix_gc!(db::IxDB) = LK.pl_garbage_collect_clauses!(db.gd, db.ld)

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
