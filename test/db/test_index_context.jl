# ORIGINAL: the re-entrance guard of the shared index_context (src/pl-index.jl); upstream declares a fresh context on the C stack per call and needs none.
# test/db/test_index_context.jl — the local data keeps ONE scratch `index_context` for
# `firstClause!`/`nextClause!` (allocation-free enumeration). That is safe only while neither is
# re-entered mid-call; the guard makes a violation loud.
include(joinpath(@__DIR__, "index_testlib.jl"))

const _IC = DefaultTerm
_ics(n) = sym_term(_IC, Symbol(n))
_icg(v) = gnd_term(_IC, v)
_ice(f, xs...) = mk_expr(_IC, _IC[_ics(f), xs...])

@testset "the shared index_context: re-entrance fails loudly" begin
    db = IxDB{_IC}()
    p = ix_pred(_IC, :p, 1; dynamic=true, db=db)
    foreach(i -> ix_assertz!(p, _ice(:p, _icg(i))), 1:20)
    goal = _ice(:p, var_term(_IC, UInt64(1)))
    @test length(ix_call(p, goal)) == 20                    # a whole enumeration…
    @test !db.ld.index_ctx.active                           # …leaves the context free
    # provoke it: a search "in progress" when another one starts
    db.ld.index_ctx.active = true
    chp = LK.ClauseChoice{_IC}(nothing, LK.word(0))
    gen = LK.global_generation(db.gd)
    @test_throws AssertionError LK.firstClause!(db.ld, goal, gen, p.def, chp)
    @test_throws AssertionError LK.nextClause!(db.ld, chp, goal, gen, p.def)
    db.ld.index_ctx.active = false
    @test LK.firstClause!(db.ld, goal, gen, p.def, chp) !== nothing   # free again: works
    @test !db.ld.index_ctx.active                           # and is released on return
end
