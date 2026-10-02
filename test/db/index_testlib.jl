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
# The kernel has no unification yet, so the CALLER unifies: `ix_match`/`ix_instance` below — a
# plain unifier (no occurs check) over the term interface, enough for these tests' facts.
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

# ── unification, the harness's own until the kernel ports it ───────────────────────────────────
# The goal's and the clause's variables live in SEPARATE spaces (a variable is `(side, var_key)`),
# as `decompile` gives each clause fresh variables; variables may repeat on either side.
"Bindings: `(is_clause_side, var_key) => (term, is_clause_side)`."
const IxBind{T} = Dict{Tuple{Bool, UInt64}, Tuple{T, Bool}}

function _ix_deref(t::T, side::Bool, b::IxBind{T})::Tuple{T, Bool} where {T}
    while kind(t) === VAR
        k = (side, var_key(t))
        haskey(b, k) || return (t, side)
        t, side = b[k]
    end
    return (t, side)
end

function _ix_unify!(x::T, sx::Bool, y::T, sy::Bool, b::IxBind{T})::Bool where {T}
    x, sx = _ix_deref(x, sx, b)
    y, sy = _ix_deref(y, sy, b)
    if kind(x) === VAR
        (kind(y) === VAR && sx == sy && var_key(x) == var_key(y)) && return true
        b[(sx, var_key(x))] = (y, sy)
        return true
    elseif kind(y) === VAR
        b[(sy, var_key(y))] = (x, sx)
        return true
    end
    kind(x) === kind(y) || return false
    if kind(x) === EXPR
        nchildren(x) == nchildren(y) || return false
        for i in 1:nchildren(x)
            _ix_unify!(child(x, i), sx, child(y, i), sy, b) || return false
        end
        return true
    end
    return compareStandard(x, y, true) == 0
end

"The bindings unifying goal `g` with clause head `h`, or `nothing`."
function ix_unify(g::T, h::T)::Union{Nothing, IxBind{T}} where {T}
    b = IxBind{T}()
    return _ix_unify!(g, false, h, true, b) ? b : nothing
end

"True when goal `g` unifies with clause head `h`."
ix_match(g::T, h::T) where {T} = ix_unify(g, h) !== nothing

function _ix_resolve(t::T, side::Bool, b::IxBind{T})::T where {T}
    t, side = _ix_deref(t, side, b)
    kind(t) === EXPR || return t
    return mk_expr(T, T[_ix_resolve(child(t, i), side, b) for i in 1:nchildren(t)])
end

"The goal `g` after unifying it with clause head `h` (which must unify)."
ix_instance(g::T, h::T) where {T} = _ix_resolve(g, false, ix_unify(g, h)::IxBind{T})

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
    c = LK.firstClause!(goal, gen, p.def, chp)
    while c !== nothing
        h = (c.clause::LK.Clause{T}).head
        if ix_match(goal, h)
            push!(out, (ix_instance(goal, h), chp.cref === nothing))
        end
        chp.cref === nothing && break
        c = LK.nextClause!(chp, goal, gen, p.def)
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
        if LK.visibleClause(cl, gen) && ix_match(goal, cl.head)
            push!(out, (ix_instance(goal, cl.head), c.next === nothing))
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
        p.db.gd, p.db.ld, p.def, goal, cl -> ix_match(goal, cl.head),
        cl -> (push!(out, ix_instance(goal, cl.head)); after(out[end]))
    )
    return out
end

"`retractall(Goal)`."
ix_retractall!(p::IxPred{T}, goal::T) where {T} =
    LK.pl_retractall!(p.db.gd, p.db.ld, p.def, goal, cl -> ix_match(goal, cl.head))

"""
    ix_clause(p, goal; after = (instance -> true)) -> [instance]

`clause(Goal, true)`, backtracking while `after(instance)` returns true; the instances, in order.
"""
function ix_clause(p::IxPred{T}, goal::T; after=(_ -> true))::Vector{T} where {T}
    out = T[]
    LK.pl_clause!(
        p.db.gd, p.db.ld, p.def, goal, cl -> ix_match(goal, cl.head),
        cl -> (push!(out, ix_instance(goal, cl.head)); after(out[end]))
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
