# ORIGINAL: the clause index's argument view (V4a); upstream exercises it only through its VM.
# test/db/test_index_argv.jl — upstream's index readers (`indexOfWord`, `canIndex`, `is_var`)
# FOLLOW REFERENCES, so a BOUND argument keys by its value and narrows the search. The kernel's
# `argv_at` dereferences through the bindings for both views of the arguments — `argv_frame`, a
# frame's argument slots (what the VM passes, where a slot almost always holds a variable bound to
# the argument), and `argv_term`, a goal's arguments. Without the dereference no bound argument
# would narrow, and the determinism the VM reports would differ from swipl's. TERM-GENERIC.
using Test, LogicKernel
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "index_testlib.jl"))
const _A = lk_term_type(Union{Int64, Float64, String})
_as(x) = lk_sym(_A, x)
_ag(x) = lk_gnd(_A, x)

"`p(1, a) … p(20, a)`, its indexes set up as a first call sets them (`setDefaultSupervisor`)."
function _a_pred()
    p = ix_pred(_A, :p, 2)
    for i in 1:20
        ix_assertz!(p, mk_expr(_A, _A[_as(:p), _ag(i), _as(:a)]))
    end
    LK.reconsiderIndexes!(p.def)
    LK.update_primary_index!(p.def)
    p.virgin = false
    return p
end

"The views of the call `p(a1, a2)`: the goal's arguments, and the same two in a frame's slots."
function _a_views(ld, a1, a2)
    base = LK.argFrameP(ld.lTop, 0)
    ld.slots[base + 1] = a1
    ld.slots[base + 2] = a2
    return (LK.argv_term(ld, mk_expr(_A, _A[_as(:p), a1, a2])), LK.argv_frame(ld, base))
end

"The first candidate and whether a clause choice is left, as `S_STATIC` asks `firstClause`."
function _a_first(p, argv)
    chp = LK.ClauseChoice{_A}(nothing, LK.word(0))
    c = LK.firstClause!(p.db.ld, argv, LK.global_generation(p.db.gd), p.def, chp)
    return c, chp.cref !== nothing
end

@testset "a bound argument narrows the index: the arguments are read dereferenced" begin
    p = _a_pred()
    ld = p.db.ld
    X, Y = mk_var(_A, UInt64(1)), mk_var(_A, UInt64(2))
    LK.Trail!(ld, var_key(X), _ag(7))                       # X = 7, then call p(X, Y)
    for argv in _a_views(ld, X, Y)
        @test LK.argv_at(argv, 0) === LK.deRef(ld, X) && lk_eq(LK.argv_at(argv, 0), _ag(7))
        c, more = _a_first(p, argv)
        @test c !== nothing && c.key == LK.indexOfWord(_ag(7))  # the clause p(7, a) …
        @test !more                                             # … and no clause choice left
    end
    @test only(ix_call(p, mk_expr(_A, _A[_as(:p), X, Y]))) |> last  # det, through ix_call too
    # a chain of bindings is followed to its end: Z = X = 7
    Z = mk_var(_A, UInt64(3))
    LK.Trail!(ld, var_key(Z), X)
    for argv in _a_views(ld, Z, Y)
        c, more = _a_first(p, argv)
        @test c !== nothing && c.key == LK.indexOfWord(_ag(7)) && !more
    end
    # unbound: every clause is a candidate, and a clause choice remains
    W = mk_var(_A, UInt64(4))
    for argv in _a_views(ld, W, Y)
        c, more = _a_first(p, argv)
        @test c !== nothing && more
    end
end
