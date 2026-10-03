# ORIGINAL: clause variables in the kernel's unification — renaming apart and who owns which variable keys; SWI's fresh variables are stack cells, unique by address, so its tests have nothing to say about keys.
# test/db/test_clause_variables.jl — the key scheme (user, 2026-10-03) and what retract/1,
# retractall/1 and clause/2 owe a caller now that they unify with the kernel's unification.
#
#   * a caller's variables have keys below KERNEL_VAR_BASE (2^63), and `var_term` rejects any other;
#   * the kernel's variables — a clause's, renamed per attempt — come from ONE process-wide counter,
#     so they are unique across attempts AND across `PL_local_data` instances: an answer retained
#     from one database and passed into another cannot collide with the other's fresh variables;
#   * a clause's variables never alias the goal's, even when the caller built both with one key;
#   * a sink sees the bindings and they are gone after it — also when it throws.
include(joinpath(@__DIR__, "index_testlib.jl"))
using LogicKernel:
    PL_local_data, pl_unify!, Mark, Undo!, deRef, resolve_term, fresh_var_keys!

const _CV = DefaultTerm
_cvs(n) = sym_term(_CV, Symbol(n))
_cvg(v) = gnd_term(_CV, v)
_cve(f, xs...) = mk_expr(_CV, _CV[_cvs(f), xs...])
_cvv(k) = var_term(_CV, UInt64(k))

"The kernel variables in `t` (keys at or above KERNEL_VAR_BASE)."
function _cvkernel(t)::Vector{UInt64}
    kind(t) === VAR && return var_key(t) >= KERNEL_VAR_BASE ? [var_key(t)] : UInt64[]
    kind(t) === EXPR || return UInt64[]
    return reduce(vcat, (_cvkernel(child(t, i)) for i in 1:nchildren(t)); init=UInt64[])
end

@testset "a caller's variables: var_term enforces the caller half" begin
    @test var_key(var_term(_CV, KERNEL_VAR_BASE - 1)) == KERNEL_VAR_BASE - 1
    @test_throws ArgumentError var_term(_CV, KERNEL_VAR_BASE)
    @test_throws ArgumentError var_term(_CV, typemax(UInt64))
    @test var_key(mk_var(_CV, KERNEL_VAR_BASE)) == KERNEL_VAR_BASE     # the raw constructor: no check
end

@testset "fresh kernel keys are unique across attempts and instances" begin
    seen = Set{UInt64}()
    n = 0
    for _ in 1:3                                            # three databases, one counter
        db = IxDB{_CV}()
        p = ix_pred(_CV, :p, 2; dynamic=true, db=db)
        ix_assertz!(p, _cve(:p, _cvv(1), _cve(:f, _cvv(2), _cvv(1))))    # p(X, f(Y, X))
        for _ in 1:500
            # p(X7, X8) = p(Xk, f(Yk, Xk)): Xk has the larger key, so it is bound to the CALLER's
            # X7 (a clause variable meeting a caller's becomes the caller's); Yk survives
            a = only(ix_clause(p, _cve(:p, _cvv(7), _cvv(8))))
            @test compareStandard(child(a, 2), _cvv(7)) == 0 &&
                compareStandard(child(child(a, 3), 3), _cvv(7)) == 0
            for k in _cvkernel(a)
                push!(seen, k)
                n += 1
            end
        end
    end
    @test n == 3 * 500                                      # Y, once per answer
    @test length(seen) == n                                 # a new key every attempt, every database
    @test all(>=(KERNEL_VAR_BASE), seen)
    b = fresh_var_keys!(4)
    @test fresh_var_keys!(1) == b + 4                       # blocks never overlap
end

# A per-database counter would start each database at the same key: `q`'s fresh A in db2 would be
# p's K from db1, so A = f(K) would be the cycle A = f(A), and resolving the answer would raise.
@testset "a retained answer moves between databases without colliding" begin
    db1, db2 = IxDB{_CV}(), IxDB{_CV}()
    p1 = ix_pred(_CV, :p, 1; dynamic=true, db=db1)
    q2 = ix_pred(_CV, :q, 2; dynamic=true, db=db2)
    ix_assertz!(p1, _cve(:p, _cve(:f, _cvv(1))))             # p(f(Y))
    ix_assertz!(q2, _cve(:q, _cvv(1), _cvs(:g)))             # q(A, g)
    for _ in 1:3
        ans = only(ix_clause(p1, _cve(:p, _cvv(5))))        # Z = f(K), K a kernel variable
        K = only(_cvkernel(ans))
        fK = child(ans, 2)
        r = only(ix_clause(q2, _cve(:q, fK, _cvv(9))))      # clause(q(f(K), W)): A = f(K), W = g
        @test compareStandard(r, _cve(:q, fK, _cvs(:g))) == 0   # no cycle: A was never K
        @test only(_cvkernel(r)) == K                       # K itself carried through, unbound
    end
    @test isempty(db1.ld.trail) && isempty(db2.ld.trail)
end

@testset "a clause's variables never alias the goal's" begin
    db = IxDB{_CV}()
    p = ix_pred(_CV, :p, 2; dynamic=true, db=db)
    ix_assertz!(p, _cve(:p, _cvv(1), _cvs(:a)))             # p(X, a), X built with key 1
    ans = ix_clause(p, _cve(:p, _cvs(:b), _cvv(1)))         # clause(p(b, X)) — the caller's X, key 1
    @test length(ans) == 1                                  # renamed apart: X(goal) = a, X(clause) = b
    @test compareStandard(only(ans), _cve(:p, _cvs(:b), _cvs(:a))) == 0
    @test ix_retract!(p, _cve(:p, _cvs(:b), _cvv(1))) |> length == 1
end

@testset "a sink sees the bindings; they are gone after it, also when it throws" begin
    db = IxDB{_CV}()
    p = ix_pred(_CV, :p, 1; dynamic=true, db=db)
    foreach(i -> ix_assertz!(p, _cve(:p, _cvg(i))), 1:3)
    X = _cvv(3)
    seen = Int[]
    LK.pl_clause!(
        db.gd,
        db.ld,
        p.def,
        _cve(:p, X),
        cl -> (push!(seen, gnd_value(deRef(db.ld, X))); true)
    )
    @test seen == [1, 2, 3]                                 # bound while the sink ran
    @test kind(deRef(db.ld, X)) === VAR                     # and unbound after
    @test_throws ErrorException LK.pl_clause!(
        db.gd, db.ld, p.def, _cve(:p, X), cl -> error("the sink fails")
    )
    @test isempty(db.ld.trail) && isempty(db.ld.bindings)   # undone on the way out
    @test isempty(db.ld.predicate_references)               # and the access popped
    @test_throws ErrorException LK.pl_retract!(
        db.gd, db.ld, p.def, _cve(:p, X), cl -> error("the sink fails")
    )
    @test isempty(db.ld.trail) && isempty(db.ld.predicate_references)
    @test length(ix_clause(p, _cve(:p, X))) == 2            # the first retract did happen
    ix_assertz!(p, _cve(:p, _cve(:h, _cvg(1))))
    @test LK.pl_retractall!(db.gd, db.ld, p.def, _cve(:p, _cve(:h, X)))  # unifies, binds X…
    @test isempty(db.ld.trail) && isempty(db.ld.bindings)   # …and undoes it per clause
    @test length(ix_clause(p, _cve(:p, X))) == 2
end
