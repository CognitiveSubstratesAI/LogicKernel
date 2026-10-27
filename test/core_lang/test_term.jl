# UPSTREAM: swipl-devel tests/core_lang/test_term.pl @ cbf4e1896275
# CLASS: code
# COPYRIGHT: Copyright (c)  2008-2020, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
#
# The `variant` unit of swipl-devel's test_term.pl — `=@=/2`, our `is_variant_ptr`
# (src/pl-variant.jl) — under upstream's unit names, each case as upstream states it; a name upstream uses more than
# once is used as often here.
#
# The rational-tree cases (`sto(rational_trees)`: cyclic ×4, cycle, ground, sharing_cycles,
# cycle_with_prefix) build their trees by unification and compare under the bindings — ported in V5a,
# when `=@=` came to take `ld`; on the CELLS since L1f f3 (`PL_unify`, `is_variant_ptr_cells`; testset
# "variant: rational trees").
#
# NOT PORTED from this unit, and why:
#   (nothing of the variant unit: its two attvar cases are ported since AV5, on the cells — testset
#   "variant: attributed variables".)
# NOT PORTED from this file: numbervars, compound, zero_arity_compound, term_singletons — builtins
# not ported yet.
using Test, LogicKernel
using LogicKernel: is_variant_ptr

# TERM TYPES PER CHUNK: ALL — the term layer: src/pl-prims.jl, src/pl-variant.jl
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _TT = lk_term_type(Union{Int64, Float64, String})
_ta(x::Symbol) = lk_sym(_TT, x)
_tc(f::Symbol, xs::_TT...) = mk_expr(_TT, _TT[_ta(f), xs...])
let n = UInt64(0)
    global _tv() = mk_var(_TT, n += 1)
end
_tl(h, t) = _tc(Symbol("[|]"), h, t)             # [H|T]

# PORT: test_term.pl dag as _tdag
"The same term as Depth cells (shared) — `f(D,D)` nested Depth deep."
function _tdag(n::Int, l::_TT)::_TT
    n == 0 && return l
    d = _tdag(n - 1, l)
    return _tc(:f, d, d)
end
# PORT: test_term.pl tree as _ttree
"…and as 2^Depth cells (unshared)."
function _ttree(n::Int, l::_TT)::_TT
    n == 0 && return l
    return _tc(:f, _ttree(n - 1, l), _ttree(n - 1, l))
end

@testset "variant" begin
    # PORT: test_term.pl simple
    @testset "simple" begin
        a, b = _tv(), _tv()
        @test is_variant_ptr(_tc(:a, a), _tc(:a, b))                   # a(A) =@= a(B)
    end
    # PORT: test_term.pl shared
    @testset "shared" begin
        a = _tv()
        @test is_variant_ptr(_tc(:a, a), _tc(:a, a))                   # a(A) =@= a(A)
    end
    # PORT: test_term.pl shared
    @testset "shared" begin
        a = _tv()
        @test is_variant_ptr(_tc(:a, a, a), _tc(:a, a, a))             # a(A,A) =@= a(A,A)
    end
    # PORT: test_term.pl shared
    @testset "shared" begin
        a, b = _tv(), _tv()
        @test is_variant_ptr(_tc(:a, a, b), _tc(:a, a, b))             # a(A,B) =@= a(A,B)
    end
    # PORT: test_term.pl shared
    @testset "shared" begin                                           # fail
        a, b = _tv(), _tv()
        @test !is_variant_ptr(_tc(:a, a, b), _tc(:a, a, a))            # a(A,B) =@= a(A,A)
    end
    # PORT: test_term.pl shared
    @testset "shared" begin                                           # fail
        a, b = _tv(), _tv()
        @test !is_variant_ptr(_tc(:a, a, b), _tc(:a, b, b))            # a(A,B) =@= a(B,B)
    end
    # PORT: test_term.pl dubious
    @testset "dubious" begin
        x, y, z = _tv(), _tv(), _tv()
        @test is_variant_ptr(_tc(:a, x, y), _tc(:a, y, z))             # a(X,Y) =@= a(Y,Z)
    end
    # PORT: test_term.pl common
    @testset "common" begin                                             # Bug #464
        a = _tc(:x, _tv())
        b = _tv()
        @test is_variant_ptr(_tc(:s, a, a), _tc(:s, _tc(:x, b), _tc(:x, b)))
    end
    # PORT: test_term.pl common
    @testset "common" begin                                           # fail
        a, b = _tv(), _tv()
        x = _tc(:x, a)
        @test !is_variant_ptr(_tc(:a, x, a), _tc(:a, x, b))            # a(X,A) =@= a(X,B)
    end
    # PORT: test_term.pl common
    @testset "common" begin                                           # fail
        a, b = _tv(), _tv()
        x = _tc(:x, a)
        @test !is_variant_ptr(_tc(:a, a, x), _tc(:a, b, x))            # a(A,X) =@= a(B,X)
    end
    # PORT: test_term.pl shared
    @testset "shared" begin                                           # fail
        a, b = _tv(), _tv()
        x, y = _tc(:x, a), _tc(:x, b)
        @test !is_variant_ptr(_tc(:s, x, y, x), _tc(:s, x, y, y))      # s(X,Y,X) =@= s(X,Y,Y)
    end
    # PORT: test_term.pl symmetry
    @testset "symmetry" begin                                           # fail — Ulrich
        x, y, z = _tv(), _tv(), _tv()
        b = _tl(x, y)                                                   # B=[X|_Y]
        c = _tl(z, x)                                                   # C=[_Z|X]
        @test !is_variant_ptr(_tl(b, c), _tl(c, b))                    # [B|C] =@= [C|B]
    end
    # PORT: test_term.pl symmetry
    @testset "symmetry" begin                                         # fail — Ulrich
        x, y, z = _tc(:s, _tv()), _tc(:s, _tv()), _tc(:s, _tv())
        @test !is_variant_ptr(_tc(:v, x, y, x), _tc(:v, z, x, y))      # v(X,Y,X) =@= v(Z,X,Y)
    end
    # PORT: test_term.pl shared_expanded
    @testset "shared_expanded" begin                                    # node buffer grows
        @test is_variant_ptr(_tdag(12, _ta(:l)), _ttree(12, _ta(:l)))
    end
    # PORT: test_term.pl shared_expanded
    @testset "shared_expanded" begin                                  # fail
        @test !is_variant_ptr(_tdag(12, _ta(:l)), _ttree(12, _ta(:m)))
    end
end

# The units' RATIONAL-TREE tests (`sto(rational_trees)`), ported once `=@=` could see bindings (V5a):
# each goal `A = T` is a unification (`occurs_check=false`), and `=@=` compares under the bindings; a
# failing conjunction is `false`. Since L1f f3 on the CELLS (the term-level `pl_unify!` and
# `is_variant_ptr(ld, …)` before): each side is put into a term reference with the case's ONE variable
# map, so a variable is one cell throughout the case. Each case runs in its own foreign frame.
const _TLD = LogicKernel.PL_local_data{_TT}(LogicKernel.PL_global_data{_TT}())
const _TPVM = Ref(LogicKernel.PutVarMap())                 # the case's variable map
"Each of `ts` put into a fresh term reference with the case's variable map; the first reference."
function _tput(ts::_TT...)::Int
    t = LogicKernel.PL_new_term_refs(_TLD, length(ts))
    for (i, x) in enumerate(ts)
        LogicKernel.putSlotValue!(_TLD, t + i, x, _TPVM[])
    end
    return t
end
_tu(a::_TT, b::_TT) = (t=_tput(a, b); LogicKernel.PL_unify(_TLD, t, t + 1))
_tvr(a::_TT, b::_TT) =
    (t=_tput(a, b); LogicKernel.is_variant_ptr_cells(_TLD, -(t + 1), -(t + 2)))
function _tcase(f)
    fid = LogicKernel.PL_open_foreign_frame(_TLD)
    _TPVM[] = LogicKernel.PutVarMap()
    try
        return f()
    finally
        LogicKernel.PL_discard_foreign_frame(_TLD, fid)
    end
end
_tnil() = mk_nil(_TT)
_tlist(xs::_TT...) = foldr(_tl, xs; init=_tnil())

@testset "variant: rational trees" begin
    # PORT: test_term.pl cyclic
    @testset "cyclic" begin                     # A = f(A), A =@= f(A).
        @test _tcase() do
            A = _tv()
            _tu(A, _tc(:f, A)) && _tvr(A, _tc(:f, A))
        end
    end
    # PORT: test_term.pl cyclic
    @testset "cyclic" begin                     # fail: S = s(S), S =@= s(s(s(s(1)))).
        @test _tcase() do                       # the setup unifies; =@= is what fails
            S = _tv()
            _tu(S, _tc(:s, S)) &&
                !_tvr(S, _tc(:s, _tc(:s, _tc(:s, _tc(:s, lk_gnd(_TT, 1))))))
        end
    end
    # PORT: test_term.pl cyclic
    @testset "cyclic" begin                     # S = s(s(S)), X = s(s(s(X))), S =@= X.
        @test _tcase() do
            S, X = _tv(), _tv()
            _tu(S, _tc(:s, _tc(:s, S))) && _tu(X, _tc(:s, _tc(:s, _tc(:s, X)))) &&
                _tvr(S, X)
        end
    end
    # PORT: test_term.pl cyclic
    @testset "cyclic" begin                     # S = s(x(S)), X = s(x(s(x(X)))), S =@= X.
        @test _tcase() do
            S, X = _tv(), _tv()
            _tu(S, _tc(:s, _tc(:x, S))) &&
                _tu(X, _tc(:s, _tc(:x, _tc(:s, _tc(:x, X))))) && _tvr(S, X)
        end
    end
    # PORT: test_term.pl cycle
    @testset "cycle" begin                      # fail — Ulrich: A=[_V1,_V2|A], D=[_V3|A], A =@= D.
        @test _tcase() do                       # the setup unifies; =@= is what fails
            A, D = _tv(), _tv()
            _tu(A, _tl(_tv(), _tl(_tv(), A))) && _tu(D, _tl(_tv(), A)) && !_tvr(A, D)
        end
    end
    # PORT: test_term.pl ground
    @testset "ground" begin                     # fail — Ulrich
        @test _tcase() do                       # A=[A|B], B=[A], D=[[A|B]|A], A=[_,_], D=[_,_,_], A =@= D.
            A, B, D = _tv(), _tv(), _tv()       # the setup unifies; =@= is what fails
            _tu(A, _tl(A, B)) && _tu(B, _tlist(A)) && _tu(D, _tl(_tl(A, B), A)) &&
                _tu(A, _tlist(_tv(), _tv())) && _tu(D, _tlist(_tv(), _tv(), _tv())) &&
                !_tvr(A, D)
        end
    end
    # PORT: test_term.pl sharing_cycles
    @testset "sharing_cycles" begin             # fail
        @test _tcase() do                       # A=[A|B], C=[A|D], B=[A|E], F=[A|F], D=[F|E], A =@= C.
            A, B, C, D, E, F = (_tv() for _ in 1:6)     # the setup unifies; =@= is what fails
            _tu(A, _tl(A, B)) && _tu(C, _tl(A, D)) && _tu(B, _tl(A, E)) &&
                _tu(F, _tl(A, F)) &&
                _tu(D, _tl(F, E)) && !_tvr(A, C)
        end
    end
    # PORT: test_term.pl cycle_with_prefix
    @testset "cycle_with_prefix" begin          # fail: A = [A|_], X = [A|Y], B = [X|Y], A =@= B.
        @test _tcase() do                       # the setup unifies; =@= is what fails
            A, X, Y, B = _tv(), _tv(), _tv(), _tv()
            _tu(A, _tl(A, _tv())) && _tu(X, _tl(A, Y)) && _tu(B, _tl(X, Y)) && !_tvr(A, B)
        end
    end
    @test isempty(_TLD.trail) && lk_no_bindings(_TLD)     # every case undone
end

# ORIGINAL (AV5): helpers for test_term.pl attvar below.
# AV5; UNRUN when written (no daemon: the run agent checks it). The two attvar units, on the cells: an
# attributed variable cannot live in the interface term, so each is made in a term reference (`put_new_attvar`,
# as test_attvar_wakeup.jl's `_wk_attvar!`) with the attribute `m = x`, and `v(…)` is built by `PL_cons_functor`.
# Upstream's answers: `v(C) =@= v(F)` true (equal attributes), `v(C,C) =@= v(C,F)` fails (the sharing differs).
"A new term reference holding an attributed variable with the attribute `m = x`."
function _tattvar()::Int
    t = LogicKernel.PL_new_term_ref(_TLD)
    x = LogicKernel.unRef(_TLD.slots[t + 1])
    LogicKernel.put_new_attvar(
        _TLD, x, LogicKernel._atom_word!(_TLD, _ta(:m)),
        (LogicKernel.DU_VALUE, LogicKernel.consInt(Int64(0)), 0)
    )
    return t
end
"`v(args…)` of the term references `args` in a new term reference."
function _tvterm(args::Int...)::Int
    t = LogicKernel.PL_new_term_ref(_TLD)
    LogicKernel.PL_cons_functor(
        _TLD, t, LogicKernel._err_functor(_TLD, :v, length(args)), args...
    )
    return t
end
@testset "variant: attributed variables" begin
    # PORT: test_term.pl attvar
    @testset "attvar" begin                     # put_attr(C,m,x), put_attr(F,m,x), v(C) =@= v(F).
        @test _tcase() do
            c, f = _tattvar(), _tattvar()
            LogicKernel.is_variant_ptr_cells(_TLD, -(_tvterm(c) + 1), -(_tvterm(f) + 1))
        end
    end
    # PORT: test_term.pl attvar
    @testset "attvar" begin                     # fail: v(C,C) =@= v(C,F).
        @test _tcase() do
            c, f = _tattvar(), _tattvar()
            !LogicKernel.is_variant_ptr_cells(
                _TLD, -(_tvterm(c, c) + 1), -(_tvterm(c, f) + 1)
            )
        end
    end
end
