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
    PL_local_data, pl_unify!, Mark, Undo!, deRef, fresh_var_keys!,
    PL_clear_exception, OCCURS_CHECK_FALSE, OCCURS_CHECK_ERROR

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _CV = lk_term_type(Union{Int64, Float64, String})
_cvs(n) = lk_sym(_CV, Symbol(n))
_cvg(v) = lk_gnd(_CV, v)
_cve(f, xs...) = mk_expr(_CV, _CV[_cvs(f), xs...])
_cvv(k) = lk_var(_CV, UInt64(k))

"The kernel variables in `t` (keys at or above KERNEL_VAR_BASE)."
function _cvkernel(t)::Vector{UInt64}
    kind(t) === VAR && return var_key(t) >= KERNEL_VAR_BASE ? [var_key(t)] : UInt64[]
    kind(t) === EXPR || return UInt64[]
    return reduce(vcat, (_cvkernel(child(t, i)) for i in 1:nchildren(t)); init=UInt64[])
end

@testset "a caller's variables: var_term enforces the caller half" begin
    @test var_key(lk_var(_CV, KERNEL_VAR_BASE - 1)) == KERNEL_VAR_BASE - 1
    @test_throws ArgumentError lk_var(_CV, KERNEL_VAR_BASE)
    @test_throws ArgumentError lk_var(_CV, typemax(UInt64))
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
            # p(X7, X8) = p(Xk, f(Yk, Xk)): X7's cell and Xk are one variable; Yk survives
            a = only(ix_clause(p, _cve(:p, _cvv(7), _cvv(8))))
            # f3-2 (audit D-0111 Q3/Q5): was `compareStandard(child(a, 2), _cvv(7)) == 0 &&
            # compareStandard(child(child(a, 3), 3), _cvv(7)) == 0` — the caller's X7 is no longer
            # handed back (f3b-1's TRANSITIONAL import_origin): the answer's X is the read's own
            # variable, one variable at both places, not X7
            @test kind(child(a, 2)) === VAR &&
                compareStandard(child(a, 2), child(child(a, 3), 3)) == 0 &&
                compareStandard(child(a, 2), _cvv(7)) != 0
            for k in _cvkernel(a)
                push!(seen, k)
                n += 1
            end
        end
    end
    # f3-2 (audit D-0111 Q3/Q5): was `n == 3 * 500` (Y, once per answer) and `length(seen) == n` —
    # X is a fresh kernel key now too (not the caller's X7): X twice and Y once per answer, two
    # distinct keys per answer
    @test n == 3 * 3 * 500                                  # X, X and Y, per answer
    @test length(seen) == 2 * 3 * 500                       # a new key every attempt and database
    @test all(>=(KERNEL_VAR_BASE), seen)
    b = fresh_var_keys!(4)
    @test fresh_var_keys!(1) == b + 4                       # blocks never overlap
end

# f3b-1 (TRANSITIONAL): a caller's variable written into a cell is bound to it, and an answer hands the
# CALLER's variable back (`resolve_term`); the cell's key maps back only while that binding stands.
@testset "an imported cell maps back to the caller's variable only while it is bound" begin
    db = IxDB{_CV}()
    p = ix_pred(_CV, :p, 2; dynamic=true, db=db)
    ix_assertz!(p, _cve(:p, _cvv(1), _cve(:f, _cvv(2), _cvv(1))))
    seen = Int[]
    for _ in 1:3
        a = only(ix_clause(p, _cve(:p, _cvv(7), _cvv(8))))
        push!(seen, length(db.ld.import_origin))             # (after the sink: undone)
        # f3-2: the keyed machinery's write sharing is gone (Q3); this testset goes in f3-3. Was
        # `var_key(child(a, 2)) == 7` — no import_origin entry is made, so the answer's variable is
        # the read's own (a kernel key), not the caller's
        @test var_key(child(a, 2)) != 7 && var_key(child(a, 2)) >= KERNEL_VAR_BASE
    end
    @test seen == [0, 0, 0] && isempty(db.ld.import_origin)  # no import outlives its binding
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
        # f3-2 (audit D-0111 Q3/Q5): was `compareStandard(r, _cve(:q, fK, _cvs(:g))) == 0` and
        # `only(_cvkernel(r)) == K` (K itself carried through) — db2's write gives K a fresh cell
        # and the answer reads it as a fresh kernel variable: q(f(_), g) up to renaming (no cycle:
        # A was never K), its one unbound variable a new key, not K
        @test LK.is_variant_ptr(r, _cve(:q, fK, _cvs(:g)))
        @test only(_cvkernel(r)) != K
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
    g = LK.PL_new_term_ref(db.ld)                           # the goal in a term reference (f3b-2b)
    LK.putSlotValue!(db.ld, g + 1, _cve(:p, X))
    gX() = child(lk_answer(db.ld, g), 2)                   # X, read through it (off the cells)
    b0 = lk_bound_count(db.ld)                              # the put's own cells: p(X) laid out
    LK.pl_clause!(db.gd, db.ld, p.def, g, cl -> (push!(seen, lk_value(gX())); true))
    @test seen == [1, 2, 3]                                 # bound while the sink ran
    @test kind(gX()) === VAR                                # and unbound after
    @test_throws ErrorException LK.pl_clause!(
        db.gd, db.ld, p.def, g, cl -> error("the sink fails")
    )
    @test isempty(db.ld.trail) && lk_bound_count(db.ld) == b0     # undone on the way out
    @test isempty(db.ld.predicate_references)               # and the access popped
    @test_throws ErrorException LK.pl_retract!(
        db.gd, db.ld, p.def, g, cl -> error("the sink fails")
    )
    @test isempty(db.ld.trail) && isempty(db.ld.predicate_references)
    @test length(ix_clause(p, _cve(:p, X))) == 2            # the first retract did happen
    ix_assertz!(p, _cve(:p, _cve(:h, _cvg(1))))
    LK.putSlotValue!(db.ld, g + 1, _cve(:p, _cve(:h, X)))
    b0 = lk_bound_count(db.ld)
    @test LK.pl_retractall!(db.gd, db.ld, p.def, g)         # unifies, binds X…
    @test isempty(db.ld.trail) && lk_bound_count(db.ld) == b0     # …and undoes it per clause
    LK.PL_reset_term_refs(db.ld, g)
    @test length(ix_clause(p, _cve(:p, X))) == 2
end

# S10 (user, 2026-10-06): an occurs-check error from a clause's head under occurs_check=error.
# swipl 10.1.16, probed with `q(Y, Y). q(a, f(a)).` and the goal head `q(A, f(A))`: retract/1 and
# retractall/1 raise the error and retract nothing; clause/2 goes on and answers from the next
# clause, the error pending (upstream checks `exception_term` only when `decompile` fails, and the
# error comes from `unify_head`).
@testset "an occurs-check error from a head: retract and retractall stop, clause goes on" begin
    db = IxDB{_CV}()
    p = ix_pred(_CV, :q, 2; dynamic=true, db=db)
    ix_assertz!(p, _cve(:q, _cvv(1), _cvv(1)))                         # q(Y, Y)
    ix_assertz!(p, _cve(:q, _cvs(:a), _cve(:f, _cvs(:a))))             # q(a, f(a))
    A = _cvv(2)
    ld = db.ld
    goal = LK.PL_new_term_ref(ld)                           # the goal in a term reference (f3b-2b)
    LK.putSlotValue!(ld, goal + 1, _cve(:q, A, _cve(:f, A)))
    pending() =
        if ld.exception_term == 0
            nothing
        else
            lk_name(child(child(lk_answer(ld, ld.exception_term), 2), 1))
        end
    ld.prolog_flag_occurs_check = OCCURS_CHECK_ERROR
    answers = 0
    LK.pl_retract!(db.gd, ld, p.def, goal, cl -> (answers += 1; true))
    @test answers == 0 && pending() === :occurs_check                  # stopped at the first
    PL_clear_exception(ld)
    @test !LK.pl_retractall!(db.gd, ld, p.def, goal)
    @test pending() === :occurs_check
    PL_clear_exception(ld)
    seen = Int[]
    LK.pl_clause!(db.gd, ld, p.def, goal, cl -> (push!(seen, 1); true))
    @test length(seen) == 1                                             # q(a, f(a)) answers
    @test pending() === :occurs_check                                   # q(Y, Y)'s error stays
    PL_clear_exception(ld)
    # the balls stay frozen below the bar (no query closes here: L1e e5a, upstream until GC) — anything
    # else bound would be a leak (audit D-0036)
    @test isempty(ld.trail) && lk_no_bindings_unfrozen(ld) &&
        isempty(ld.predicate_references)
    LK.PL_reset_term_refs(ld, goal)
    ld.prolog_flag_occurs_check = OCCURS_CHECK_FALSE
    @test length(ix_clause(p, _cve(:q, _cvv(3), _cvv(4)))) == 2         # nothing was retracted
end
