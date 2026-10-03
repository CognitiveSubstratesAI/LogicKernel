# UPSTREAM: swipl-devel tests/db/test_db.pl @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  2009-2020, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
#
# SWI-Prolog's own tests of the core database functions, the `retract` and `retractall` units the
# clause database can run (src/pl-proc.jl), through test/db/index_testlib.jl. Unification is the
# harness's until it is ported.
#
# NOT PORTED YET: the `assert` units (cyclic heads, maximum arity, a body with a cut — they need
# clause bodies and the compiler), `retract` theorist ×2 (rules with bodies), `qhead` (modules),
# `concurrent` (threads), `retractall` type(callable) (the API takes a predicate, not a term), and
# the `dynamic`, `protect` and `res_compiler` units.
include(joinpath(@__DIR__, "index_testlib.jl"))

include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _D = lk_term_type(Union{Int64, Float64, String})
_ds(n) = lk_sym(_D, Symbol(n))
_dg(v) = lk_gnd(_D, v)
_de(f, xs...) = mk_expr(_D, _D[_ds(f), xs...])
let n = UInt64(0)
    global _dv() = mk_var(_D, n += 1)
end
"The head `name(_, …)` of predicate `p`, every argument a fresh variable."
_dall(p::IxPred{_D}, name::Symbol) = _de(name, (_dv() for _ in 1:(p.def.arity))...)

@testset "retract" begin
    db = IxDB{_D}()                                 # one module: one database
    foo = ix_pred(_D, :foo, 1; dynamic=true, db=db) # :- dynamic foo/1, insect/1, icopy/1.
    insect = ix_pred(_D, :insect, 1; dynamic=true, db=db)
    icopy = ix_pred(_D, :icopy, 1; dynamic=true, db=db)
    # PORT: test_db.pl fact
    @testset "fact" begin
        try
            ix_assertz!(foo, _de(:foo, _dg(1)))                    # assert(foo(1))
            r = ix_retract!(foo, _de(:foo, _dv()); after=_ -> false)   # retract(foo(X))
            @test length(r) == 1 && lk_eq(child(r[1], 2), _dg(1))       # X == 1
        finally
            ix_retractall!(foo, _dall(foo, :foo))
        end
    end
    # PORT: test_db.pl rule
    @testset "rule" begin
        # retract((foo(X):-true)): a fact's body is `true`, so this is retract(foo(X))
        try
            ix_assertz!(foo, _de(:foo, _dg(1)))
            r = ix_retract!(foo, _de(:foo, _dv()); after=_ -> false)
            @test length(r) == 1 && lk_eq(child(r[1], 2), _dg(1))
        finally
            ix_retractall!(foo, _dall(foo, :foo))
        end
    end
    # PORT: test_db.pl update_view
    @testset "update_view" begin
        ix_retractall!(insect, _dall(insect, :insect))             # retractall(insect(_))
        ix_retractall!(icopy, _dall(icopy, :icopy))                # retractall(icopy(_))
        ix_assertz!(insect, _de(:insect, _ds(:ant)))
        ix_assertz!(insect, _de(:insect, _ds(:bee)))
        # (retract(insect(I)), assertz(icopy(I)), retract(insect(bee)), fail ; …)
        ix_retract!(
            insect, _de(:insect, _dv());
            after=inst -> begin
                ix_assertz!(icopy, _de(:icopy, child(inst, 2)))
                ix_retract!(insect, _de(:insect, _ds(:bee)); after=_ -> false)
                true                                                # fail: backtrack
            end
        )
        # findall(I, retract(icopy(I)), L)
        l = [child(i, 2) for i in ix_retract!(icopy, _de(:icopy, _dv()))]
        @test lk_eq(l, [_ds(:ant), _ds(:bee)])                          # L == [ant,bee]
    end
end

@testset "retractall" begin
    db = IxDB{_D}()
    dbp = ix_pred(_D, :db, 2; dynamic=true, db=db)                 # :- dynamic db/2.
    # PORT: test_db.pl init_db
    "init_db :- forall(between(1,2,X), forall(between(1,2,Y), assert(db(X,Y))))."
    function init_db()
        for x in 1:2, y in 1:2
            ix_assertz!(dbp, _de(:db, _dg(x), _dg(y)))
        end
    end
    # PORT: test_db.pl clear_db
    "clear_db :- retractall(db(_,_))."
    clear_db() = ix_retractall!(dbp, _dall(dbp, :db))
    "findall(db(X,Y), db(X,Y), All)"
    all_db() = [a for (a, _) in ix_call(dbp, _de(:db, _dv(), _dv()))]
    # PORT: test_db.pl all
    @testset "all" begin
        init_db()
        try
            ix_retractall!(dbp, _de(:db, _dv(), _dv()))           # retractall(db(_,_))
            @test lk_eq(all_db(), _D[])                                 # All=[]
        finally
            clear_db()
        end
    end
    # PORT: test_db.pl one
    @testset "one" begin
        init_db()
        try
            ix_retractall!(dbp, _de(:db, _dg(1), _dv()))          # retractall(db(1,_))
            @test lk_eq(all_db(), [_de(:db, _dg(2), _dg(1)), _de(:db, _dg(2), _dg(2))])
        finally
            clear_db()
        end
    end
    # PORT: test_db.pl shared
    @testset "shared" begin
        init_db()
        try
            x = _dv()
            ix_retractall!(dbp, _de(:db, x, x))                    # retractall(db(X,X))
            @test lk_eq(all_db(), [_de(:db, _dg(1), _dg(2)), _de(:db, _dg(2), _dg(1))])
        finally
            clear_db()
        end
    end
    # PORT: test_db.pl type
    @testset "type" begin
        # retractall(retractall(_)): permission_error(modify, static_procedure, _) — a static
        # predicate with clauses
        st = ix_pred(_D, :static, 1; db=db)
        ix_assertz!(st, _de(:static, _dg(1)))
        @test_throws ErrorException ix_retractall!(st, _de(:static, _dv()))
    end
end
