# UPSTREAM: swipl-devel tests/core_lang/test_unify.pl @ 8e1bc1110be4
# CLASS: code
# COPYRIGHT: Copyright (c)  2008-2024, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# swipl-devel's test_unify.pl — "unification oddities" — against `PL_unify`, `?=/2` (`pl_can_compare2_va`)
# and `unifiable_cells` (src/pl-prims.jl) on the CELLS (since L1f f3; the term-level `pl_unify!`,
# `pl_can_compare` and `unifiable` before), under upstream's unit names; a name upstream uses more than
# once is used as often here. Each unit runs in fresh local data and leaves its bindings undone.
#
# DIVERGES (file-wide): `blam` and `unify_self` replay the unifications of upstream's successful
# derivation (named per case), on terms put into term references with ONE variable map (`_uput`: a
# variable shared between them is one cell); an answer is read off the cells (`lk_answer`/`lk_answers`).
#
# NOT PORTED, and why:
#   unify_fv   garbage_collect/0 and copy_term/2 on an uninitialised variable — the kernel has no
#              stacks to collect, and copy_term/2 is not ported.
#   gc_1       attributed variables (freeze/2) — the kernel has none.
using Test, LogicKernel
using LogicKernel: PL_local_data, PL_global_data, PL_unify, Mark, Undo!
const LK = LogicKernel

# TERM TYPES PER CHUNK: ALL — the term layer: src/pl-prims.jl
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _UT = lk_term_type(Union{Int64, Float64, String})
_us(x::Symbol) = lk_sym(_UT, x)
_ug(x) = lk_gnd(_UT, x)
_uc(f::Symbol, xs::_UT...) = mk_expr(_UT, _UT[_us(f), xs...])
_uv(k::Int) = mk_var(_UT, UInt64(k))
_unil() = mk_nil(_UT)                                       # SWI-7's [], reserved
_ucons(h, t) = _uc(Symbol("[|]"), h, t)                     # [H|T]
_uid(a, b) = compareStandard(a, b) == 0                     # ==/2
"Fresh local data with each of `vs` put into a term reference of its own, ONE variable map; `(ld, t)`, `vs[i]` in reference `t + i - 1`."
function _uput(vs::_UT...)
    ld = PL_local_data{_UT}(PL_global_data{_UT}())
    t = LK.PL_new_term_refs(ld, length(vs))
    pvm = LK.PutVarMap()
    for (i, v) in enumerate(vs)
        LK.putSlotValue!(ld, t + i, v, pvm)
    end
    return ld, t
end
"Whether term reference `r` holds a reference to an unbound cell (nothing bound it)."
_ufree(ld, r) = LK.isRef(ld.slots[r + 1]) && ld.gstack[LK.unRef(ld.slots[r + 1])] == 0
"`?=(A1, A2)` on two consecutive term references from `t` (`pl_can_compare2_va`)."
_ucan_compare(ld, t) =
    LK.pl_can_compare2_va(
        ld, t, 2, LK.foreign_context{_UT}(LK.FRG_FIRST_CALL, UInt(0), nothing)
    ) ==
    LK.FTRUE

@testset "unify" begin
    # PORT: test_unify.pl blam
    # blam([]).  blam([L|L]) :- blam(L).   blam(X), length(X, 2): the successful derivation binds
    # X = [L|L], L = [L2|L2], L2 = [] — so X == [[[]], []].
    @testset "blam" begin
        X, L, L2 = _uv(1), _uv(2), _uv(3)
        ld, t = _uput(X, _ucons(L, L), L, _ucons(L2, L2), L2, _unil())
        @test PL_unify(ld, t, t + 1)
        @test PL_unify(ld, t + 2, t + 3)
        @test PL_unify(ld, t + 4, t + 5)
        expected = _ucons(_ucons(_unil(), _unil()), _ucons(_unil(), _unil()))
        @test _uid(lk_answer(ld, t), expected)             # X == [[[]], []]
    end
    # PORT: test_unify.pl unify_self
    # p/2 runs U=U, V=V (Bug#436): unifying a variable with itself binds nothing.
    @testset "unify_self" begin
        ld, t = _uput(_uv(1), _uv(2))                       # U, V
        @test PL_unify(ld, t, t) && PL_unify(ld, t + 1, t + 1)
        @test isempty(ld.trail) && _ufree(ld, t) && _ufree(ld, t + 1)
    end
    # PORT: test_unify.pl unify_arity_0
    @testset "unify_arity_0" begin                           # A = f(), X == f()
        ld, t = _uput(_uv(1), _uc(:f), _uc(:f), _us(:f))
        @test PL_unify(ld, t, t + 1)
        @test _uid(lk_answer(ld, t), _uc(:f))
        m = Mark(ld)
        @test !PL_unify(ld, t + 2, t + 3)                   # f() is not the atom f
        Undo!(ld, m)
    end
    # PORT: test_unify.pl cycle_1
    @testset "cycle_1" begin                                 # Kuniaki Mukai
        X, Y = _uv(1), _uv(2)
        ld, t = _uput(X, _uc(:f, Y), Y, _uc(:f, X))
        @test PL_unify(ld, t, t + 1)                        # X = f(Y),
        @test PL_unify(ld, t + 2, t + 3)                    # Y = f(X),
        @test PL_unify(ld, t, t + 2)                        # X = Y.
    end
    # PORT: test_unify.pl cycle_2
    @testset "cycle_2" begin                                 # Kuniaki Mukai
        X, Y = _uv(1), _uv(2)
        ld, t = _uput(X, _uc(:f, X), Y, _uc(:f, Y), _uc(:f, Y))
        @test PL_unify(ld, t, t + 1)                        # X = f(X),
        @test PL_unify(ld, t + 2, t + 3)                    # Y = f(Y),
        @test PL_unify(ld, t, t + 4)                        # X = f(Y).
    end
end

@testset "can_compare" begin
    # PORT: test_unify.pl ground
    @testset "ground" begin
        @test _ucan_compare(_uput(_us(:a), _us(:b))...)    # ?=(a,b)
    end
    # PORT: test_unify.pl ground
    @testset "ground" begin
        @test _ucan_compare(_uput(_us(:a), _us(:a))...)    # ?=(a,a)
    end
    # PORT: test_unify.pl ground
    @testset "ground" begin                                  # fail
        ld, t = _uput(_us(:a), _uv(1))
        @test !_ucan_compare(ld, t)                         # ?=(a,X)
        @test _ufree(ld, t + 1)                             # nothing left bound
    end
end

@testset "unifiable" begin
    # PORT: test_unify.pl unifiable_1
    @testset "unifiable_1" begin                             # S == [X=1]
        X = _uv(1)
        ld, t = _uput(X, _ug(1), _uv(9))
        @test LK.unifiable_cells(ld, t, t + 1, t + 2)
        x, s = lk_answers(ld, t, t + 2)
        @test _uid(s, _ucons(_uc(:(=), x, _ug(1)), _unil()))
    end
    # PORT: test_unify.pl unifiable_2
    @testset "unifiable_2" begin                             # S == [Z=X, Y=X]
        X, Y, Z = _uv(1), _uv(2), _uv(3)                    # created in that order, as upstream's
        ld, t = _uput(_uc(:a, X, X), _uc(:a, Y, Z), _uv(9), X, Y, Z)
        @test LK.unifiable_cells(ld, t, t + 1, t + 2)
        s, x, y, z = lk_answers(ld, t + 2, t + 3, t + 4, t + 5)
        @test _uid(s, _ucons(_uc(:(=), z, x), _ucons(_uc(:(=), y, x), _unil())))
        @test _ufree(ld, t + 3) && _ufree(ld, t + 4) && _ufree(ld, t + 5)   # read off the trail, rewound
    end
end
