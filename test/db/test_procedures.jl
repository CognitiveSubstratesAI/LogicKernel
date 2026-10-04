# ORIGINAL: the predicate table of a database (V1; user, 2026-10-04); swipl has no unit test of lookupProcedure, so these pin the upstream behaviour the kernel ports.
# test/db/test_procedures.jl — the database's user module and its procedure table (src/pl-proc.jl
# `lookupProcedure`, `isCurrentProcedure`, `hasClausesDefinition`, `isDefinedProcedure`,
# `setDynamicDefinition!`; src/pl-global.jl `MODULE_user`). TERM-GENERIC: runtests.jl runs it on
# every implementation.
#   * ONE way to get a predicate (user, 2026-10-04): `lookupProcedure` finds the functor's procedure
#     or creates it, so the same functor gives the same procedure; a fresh predicate is a predicate of
#     a fresh database;
#   * the key is the FUNCTOR, the name's identity and the arity: `p/1` and `p/2` differ, and so do
#     `[]/0` (the reserved symbol) and `'[]'/0` (the text atom);
#   * `:- dynamic` is `setDynamicDefinition!`: `P_DYNAMIC|P_TRANSACT`, idempotent, reversible;
#   * defined is a `PROC_DEFINED` flag or a clause visible NOW: for a dynamic predicate
#     `hasClausesDefinition` walks past the erased clauses.
include(joinpath(@__DIR__, "index_testlib.jl"))
include(joinpath(@__DIR__, "..", "term_under_test.jl"))

const _P = lk_term_type(Union{Int64, Float64})
_ps(n) = lk_sym(_P, Symbol(n))
_pe(f, xs::_P...) = mk_expr(_P, _P[_ps(f), xs...])
_pg(v) = lk_gnd(_P, v)

@testset "one procedure per functor and database" begin
    gd = LK.PL_global_data{_P}()
    user = LK.MODULE_user(gd)
    @test user === LK.MODULE_user(gd)
    @test user.name == sym_key(_ps(:user))
    p = sym_key(_ps(:p))
    @test LK.isCurrentProcedure(p, 1, user) === nothing
    p1 = LK.lookupProcedure(p, 1, user)
    @test LK.isCurrentProcedure(p, 1, user) === p1
    @test LK.lookupProcedure(p, 1, user) === p1                 # found, not created again
    p2 = LK.lookupProcedure(p, 2, user)
    @test p2 !== p1 && p2.definition !== p1.definition          # the arity is part of the functor
    @test length(user.procedures) == 2
    d = p2.definition                                           # a new predicate
    @test d.functor_name == p && d.arity == 2 && d.flags == 0 && p2.flags == 0
    @test d.impl_clauses.first_clause === nothing && d.impl_clauses.number_of_clauses == 0
    @test length(d.impl_clauses.args::Vector{LK.arg_info}) == 2
    @test LK.lookupProcedure(sym_key(_ps(:q)), 0, user).definition.impl_clauses.args ===
        nothing
    other = LK.MODULE_user(LK.PL_global_data{_P}())             # another database, another table
    @test LK.lookupProcedure(p, 1, other) !== p1
    @test LK.isCurrentProcedure(p, 2, other) === nothing
end

@testset "the functor's name is the symbol's identity: [] is not '[]'" begin
    user = LK.MODULE_user(LK.PL_global_data{_P}())
    nil = LK.lookupProcedure(sym_key(mk_nil(_P)), 0, user)
    text = LK.lookupProcedure(sym_key(_ps("[]")), 0, user)
    @test nil !== text
    @test LK.lookupProcedure(sym_key(mk_nil(_P)), 0, user) === nil
end

@testset ":- dynamic is setDynamicDefinition!" begin
    d =
        LK.lookupProcedure(sym_key(_ps(:d)), 1, LK.MODULE_user(LK.PL_global_data{_P}())).definition
    @test LK.setDynamicDefinition!(d, true)
    @test d.flags & (LK.P_DYNAMIC | LK.P_TRANSACT) == LK.P_DYNAMIC | LK.P_TRANSACT
    @test LK.setDynamicDefinition!(d, true)                     # already dynamic: unchanged
    @test d.flags & (LK.P_DYNAMIC | LK.P_TRANSACT) == LK.P_DYNAMIC | LK.P_TRANSACT
    @test LK.setDynamicDefinition!(d, false)
    @test d.flags & (LK.P_DYNAMIC | LK.P_TRANSACT) == 0
end

@testset "defined: a PROC_DEFINED flag or a clause visible now" begin
    db = IxDB{_P}()
    s = ix_pred(_P, :s, 1; db=db)                               # static, no clauses
    @test !LK.isDefinedProcedure(db.gd, s.proc)
    @test LK.hasClausesDefinition(db.gd, s.def) === nothing
    ix_assertz!(s, _pe(:s, _pg(1)))
    @test LK.isDefinedProcedure(db.gd, s.proc)
    @test LK.hasClausesDefinition(db.gd, s.def) === s.def.impl_clauses.first_clause
    d = ix_pred(_P, :d, 1; dynamic=true, db=db)
    @test LK.isDefinedProcedure(db.gd, d.proc)                  # dynamic: defined, no clauses
    @test LK.hasClausesDefinition(db.gd, d.def) === nothing
    ix_assertz!(d, _pe(:d, _pg(1)))
    ix_assertz!(d, _pe(:d, _pg(2)))
    first = d.def.impl_clauses.first_clause
    @test LK.hasClausesDefinition(db.gd, d.def) === first
    @test length(ix_retract!(d, _pe(:d, _pg(1)))) == 1          # d(1) erased, still in the chain
    gen = LK.global_generation(db.gd)
    @test d.def.impl_clauses.first_clause === first &&
        !LK.visibleClauseCNT(first.clause, gen)
    r = LK.hasClausesDefinition(db.gd, d.def)                   # the walk skips it
    @test r !== nothing && r !== first && LK.visibleClauseCNT(r.clause, gen)
    @test length(ix_retract!(d, _pe(:d, _pg(2)))) == 1
    @test LK.hasClausesDefinition(db.gd, d.def) === nothing
    @test LK.isDefinedProcedure(db.gd, d.proc)                  # still dynamic
    for f in (LK.P_FOREIGN, LK.P_MULTIFILE, LK.P_DISCONTIGUOUS, LK.P_LOCKED_SUPERVISOR)
        q = ix_pred(_P, :q, 1)                                  # a fresh database each time
        @test !LK.isDefinedProcedure(q.db.gd, q.proc)
        q.def.flags |= f
        @test LK.isDefinedProcedure(q.db.gd, q.proc)
    end
end
