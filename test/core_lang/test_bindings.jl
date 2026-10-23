# ORIGINAL: properties of the kernel's trail on the cells (src/pl-inline.jl, src/pl-prims.jl) that SWI's tests cannot state.
# test/core_lang/test_bindings.jl — what `Mark`/`Undo!` and the cell unifier promise: marks nest (undoing
# to a mark above the trail's top is a misuse, asserted), and a failed unification leaves its partial
# bindings until the caller undoes (as SWI). Upstream's own units are in test_unify.jl and
# test_occurs_check.jl; the live differential against swipl is test_unify_swipl.jl. (f3-3: the keyed
# binding store's testsets — its DIVERGES, `resolve_term`, the warm attempt's allocations — went with it.)
using Test, LogicKernel
using LogicKernel: PL_local_data, PL_global_data, Mark, Undo!

# TERM TYPES PER CHUNK: ALL — the trail and the cell unifier: src/pl-inline.jl, src/pl-prims.jl
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _BT = lk_term_type(Union{Int64, Float64, String})
_bs(x::Symbol) = lk_sym(_BT, x)
_bg(x) = lk_gnd(_BT, x)
_bc(f::Symbol, xs::_BT...) = mk_expr(_BT, _BT[_bs(f), xs...])
_bv(k::Int) = mk_var(_BT, UInt64(k))
_bid(a, b) = compareStandard(a, b) == 0

"An engine with the values `vs` put with one variable map; `(ld, t)` (reference `t + i - 1` is slot `t + i`)."
function _bengine(vs::Vector{_BT})
    ld = PL_local_data{_BT}(PL_global_data{_BT}())
    t = LogicKernel.PL_new_term_refs(ld, length(vs))
    pvm = LogicKernel.PutVarMap()
    for (i, v) in enumerate(vs)
        LogicKernel.putSlotValue!(ld, t + i, v, pvm)
    end
    return ld, t
end
"Unify term references `i` and `j` on the cells (`do_unify_cells`)."
_bu(ld, i::Int, j::Int)::Bool =
    LogicKernel.do_unify_cells(ld, -(i + 1), -(j + 1)) == LogicKernel.BOOLEX_TRUE

@testset "the trail: Mark and Undo!" begin
    X, Y, Z = _bv(1), _bv(2), _bv(3)
    # references: t X, t+1 Y, t+2 Z, t+3 a, t+4 g(Z), t+5 2, t+6 b, t+7 p(Y, a), t+8 p(c, b)
    ld, t = _bengine(
        _BT[X, Y, Z, _bs(:a), _bc(:g, Z), _bg(2), _bs(:b), _bc(:p, Y, _bs(:a)),
            _bc(:p, _bs(:c), _bs(:b))]
    )
    b0 = lk_bound_count(ld)                                 # the puts' own cells
    m0 = Mark(ld)
    @test _bu(ld, t, t + 3)                                 # X = a
    m1 = Mark(ld)
    @test _bu(ld, t + 1, t + 4) && _bu(ld, t + 2, t + 5)    # Y = g(Z), Z = 2
    @test _bid(lk_answer(ld, t + 1), _bc(:g, _bg(2)))
    Undo!(ld, m1)                                           # back to just X = a
    x, y, z = lk_answers(ld, t, t + 1, t + 2)
    @test _bid(x, _bs(:a)) && kind(y) === VAR && kind(z) === VAR
    @test length(ld.trail) == 1
    Undo!(ld, m0)
    @test isempty(ld.trail) && lk_bound_count(ld) == b0
    # marks nest: undoing to a mark above the trail's top is a misuse, and asserted
    m2 = Mark(ld)
    @test _bu(ld, t, t + 6)                                 # X = b
    m3 = Mark(ld)
    Undo!(ld, m2)
    @test_throws AssertionError Undo!(ld, m3)
    # a failed unification leaves its partial bindings until the caller undoes (as SWI)
    m4 = Mark(ld)
    @test !_bu(ld, t + 7, t + 8)                            # p(Y, a) = p(c, b)
    @test _bid(lk_answer(ld, t + 1), _bs(:c))               # Y = c was made before the failure
    Undo!(ld, m4)
    @test kind(lk_answer(ld, t + 1)) === VAR
end
