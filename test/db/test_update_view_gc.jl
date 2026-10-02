# ORIGINAL: the logical update view under clause garbage collection, against swipl; upstream's suites have no unit for an enumeration that outlives a collected clause.
# test/db/test_update_view_gc.jl — what clause GC owes an enumeration that is still running.
#
# An enumeration runs in the generation it started in (the LOGICAL UPDATE VIEW): a clause retracted
# after it started is still enumerated, even when clause GC runs in between — GC may only unlink
# clauses no generation IN USE can see, so an enumeration must register its generation
# (`pushPredicateAccessObj!`). Unlinking `p(3)` early would cut `p(2)`'s `next`, and the
# enumeration would end at `p(2)`.
#
# The `assertz(r(_))` between the retract and the collection matters: clause GC never collects a
# clause erased at or after its START generation, so without a newer generation `p(3)` is safe by
# that rule alone and the enumeration's registration goes untested (measured: a mutation that
# ignores every registration passed until the generation was advanced).
#
# Expected values were measured on swipl 10.1.16 (2026-10-02) and are ALSO re-checked live:
#   findall(X, (clause(p(X), true),
#               (X == 1 -> retract(p(3)), assertz(r(1)), garbage_collect_clauses ; true)), L)
#       L == [1,2,3];  afterwards findall(X, p(X), L2): L2 == [1,2]
#   findall(X, (retract(q(X)),
#               (X == 1 -> retract(q(3)), assertz(r(2)), garbage_collect_clauses ; true)), L)
#       L == [1,2,3]  — retract/1 on redo yields q(3) though the inner retract erased it first
include(joinpath(@__DIR__, "index_testlib.jl"))

const _U = DefaultTerm
_us(n) = sym_term(_U, Symbol(n))
_ug(v) = gnd_term(_U, v)
_ue(f, xs...) = mk_expr(_U, _U[_us(f), xs...])
let n = UInt64(0)
    global _uv() = mk_var(_U, n += 1)
end

"Run the two enumerations in the kernel; the three answer lists, as integers."
function _uv_kernel()
    db = IxDB{_U}()
    p = ix_pred(_U, :p, 1; dynamic=true, db=db)
    q = ix_pred(_U, :q, 1; dynamic=true, db=db)
    r = ix_pred(_U, :r, 1; dynamic=true, db=db)
    for i in 1:3
        ix_assertz!(p, _ue(:p, _ug(i)))
        ix_assertz!(q, _ue(:q, _ug(i)))
    end
    xval(i) = gnd_value(child(i, 2))::Int
    l1 = xval.(
        ix_clause(p, _ue(:p, _uv());
            after=i -> (
                xval(i) == 1 && (ix_retract!(p, _ue(:p, _ug(3)); after=_ -> false);
                    ix_assertz!(r, _ue(:r, _ug(1))); ix_gc!(db)); true))
    )
    l2 = [xval(a) for (a, _) in ix_call(p, _ue(:p, _uv()))]
    l3 = xval.(
        ix_retract!(q, _ue(:q, _uv());
            after=i -> (
                xval(i) == 1 && (ix_retract!(q, _ue(:q, _ug(3)); after=_ -> false);
                    ix_assertz!(r, _ue(:r, _ug(2))); ix_gc!(db)); true))
    )
    return (l1, l2, l3)
end

const _UV_PROGRAM = raw"""
:- dynamic p/1, q/1, r/1.
:- initialization(main, main).
main :-
    assertz(p(1)), assertz(p(2)), assertz(p(3)),
    findall(X, (clause(p(X), true), (X == 1 -> retract(p(3)), assertz(r(1)), garbage_collect_clauses ; true)), L1),
    findall(X, p(X), L2),
    assertz(q(1)), assertz(q(2)), assertz(q(3)),
    findall(X, (retract(q(X)), (X == 1 -> retract(q(3)), assertz(r(2)), garbage_collect_clauses ; true)), L3),
    print(L1), nl, print(L2), nl, print(L3), nl.
"""

const _UV_SWIPL = Sys.which("swipl")
const _UV_REQUIRED = get(ENV, "LOGICKERNEL_REQUIRE_SWIPL", "") == "1"

@testset "logical update view under clause GC" begin
    l1, l2, l3 = _uv_kernel()
    @testset "pinned (swipl 10.1.16)" begin
        @test l1 == [1, 2, 3]       # clause/2 still enumerates the retracted, collected p(3)
        @test l2 == [1, 2]          # a call started afterwards does not
        @test l3 == [1, 2, 3]       # retract/1 yields q(3) on redo though already erased
    end
    if _UV_SWIPL !== nothing
        @testset "identical to swipl" begin
            out = mktempdir() do d
                f = joinpath(d, "uv.pl")
                write(f, _UV_PROGRAM)
                split(read(`swipl -q $f`, String), '\n'; keepempty=false)
            end
            @test length(out) == 3
            @test out == ["[" * join(l, ",") * "]" for l in (l1, l2, l3)]
        end
    elseif _UV_REQUIRED
        error(
            "LOGICKERNEL_REQUIRE_SWIPL=1 but `swipl` is not on PATH — the update-view check would be skipped"
        )
    else
        @info "UPDATE VIEW vs swipl NOT RUN: `swipl` is not on PATH here. It runs in tools/run_tests.sh and CI's analysis job."
        @testset "swipl comparison skipped only where it is not required" begin
            @test !_UV_REQUIRED
        end
    end
end
