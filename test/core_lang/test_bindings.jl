# ORIGINAL: properties of the kernel's binding store and trail (src/pl-inline.jl, src/pl-prims.jl) that SWI's tests cannot state — SWI's bindings are cells, not a store.
# test/core_lang/test_bindings.jl — what `Trail!`/`Mark`/`Undo!`, the unifier's DIVERGES and
# `resolve_term` promise. Upstream's own units are in test_unify.jl and test_occurs_check.jl; the
# live differential against swipl is test_unify_swipl.jl.
using Test, LogicKernel
using LogicKernel:
    PL_local_data, pl_unify!, Mark, Undo!, deRef, resolve_term, OCCURS_CHECK_FALSE

const _BT = DefaultTerm
_bs(x::Symbol) = sym_term(_BT, x)
_bg(x) = gnd_term(_BT, x)
_bc(f::Symbol, xs::_BT...) = mk_expr(_BT, _BT[_bs(f), xs...])
_be(xs::_BT...) = mk_expr(_BT, _BT[xs...])
_bv(k::Int) = mk_var(_BT, UInt64(k))
_bid(a, b) = compareStandard(a, b) == 0

"Unify `a` and `b` and undo: one attempt of a search, as a sink-driven caller makes it."
function _battempt!(ld, a, b)::Bool
    m = Mark(ld)
    r = pl_unify!(ld, a, b)
    Undo!(ld, m)
    return r
end

let n = UInt64(100)
    global _bfresh() = mk_var(_BT, n += 1)
end

"An `f/2` tree of depth `d`, each leaf `leaf()`."
_btree(d::Int, leaf) = d == 0 ? leaf() : _bc(:f, _btree(d - 1, leaf), _btree(d - 1, leaf))

@testset "the trail: Mark and Undo!" begin
    ld = PL_local_data{_BT}()
    X, Y, Z = _bv(1), _bv(2), _bv(3)
    m0 = Mark(ld)
    @test pl_unify!(ld, X, _bs(:a))
    m1 = Mark(ld)
    @test pl_unify!(ld, Y, _bc(:g, Z)) && pl_unify!(ld, Z, _bg(2))
    @test _bid(resolve_term(ld, Y), _bc(:g, _bg(2)))
    Undo!(ld, m1)                                           # back to just X = a
    @test _bid(deRef(ld, X), _bs(:a)) && kind(deRef(ld, Y)) === VAR &&
        kind(deRef(ld, Z)) === VAR
    @test length(ld.trail) == 1
    Undo!(ld, m0)
    @test isempty(ld.trail) && isempty(ld.bindings)
    # marks nest: undoing to a mark above the trail's top is a misuse, and asserted
    m2 = Mark(ld)
    @test pl_unify!(ld, X, _bs(:b))
    m3 = Mark(ld)
    Undo!(ld, m2)
    @test_throws AssertionError Undo!(ld, m3)
    # a failed unification leaves its partial bindings until the caller undoes (as SWI)
    m4 = Mark(ld)
    @test !pl_unify!(ld, _bc(:p, Y, _bs(:a)), _bc(:p, _bs(:c), _bs(:b)))
    @test _bid(deRef(ld, Y), _bs(:c))                       # Y = c was made before the failure
    Undo!(ld, m4)
    @test kind(deRef(ld, Y)) === VAR
end

@testset "DIVERGES: two variables — the larger var_key is bound to the smaller" begin
    ld = PL_local_data{_BT}()
    @test pl_unify!(ld, _bv(5), _bv(3))
    @test haskey(ld.bindings, UInt64(5)) && !haskey(ld.bindings, UInt64(3))
    @test pl_unify!(ld, _bv(7), _bv(9))
    @test haskey(ld.bindings, UInt64(9)) && !haskey(ld.bindings, UInt64(7))
    @test pl_unify!(ld, _bv(4), mk_var(_BT, UInt64(4)))     # one variable, two term objects
    @test !haskey(ld.bindings, UInt64(4))
end

@testset "DIVERGES: compounds without a symbol head unify child by child" begin
    ld = PL_local_data{_BT}()
    X = _bv(1)
    @test _battempt!(ld, _be(X, _bs(:a)), _bc(:f, _bs(:a)))          # (X a) = f(a): X = f
    @test _battempt!(ld, _be(_bc(:g), _bs(:a)), _be(_bc(:g), _bs(:a)))   # compound heads
    @test !_battempt!(ld, _be(X), _bc(:f, _bs(:a)))                   # child counts differ
    @test _battempt!(ld, _be(), _be())                                # () = ()
    @test !_battempt!(ld, _be(), _bc(:f))                             # () is not f()
    @test !_battempt!(ld, _bc(:f, _bs(:a)), _bc(:g, _bs(:a)))         # symbol heads: functor
    @test pl_unify!(ld, _be(X, _bs(:a)), _bc(:f, _bs(:a)))
    @test _bid(deRef(ld, X), _bs(:f))
end

@testset "resolve_term" begin
    ld = PL_local_data{_BT}()
    X, Y, Z = _bv(1), _bv(2), _bv(3)
    big = _btree(4, () -> _bs(:a))                          # ground: shared, never rebuilt
    @test pl_unify!(ld, X, _bc(:h, Y, big, Z)) && pl_unify!(ld, Y, _bg(1))
    r = resolve_term(ld, X)
    @test _bid(r, _bc(:h, _bg(1), big, Z))                  # Z unbound: stays a variable
    @test child(r, 3) === big
    @test pl_unify!(ld, Z, _bc(:k, X))                      # X = h(1, big, k(X)): cyclic
    @test_throws ArgumentError resolve_term(ld, X)          # SWI would return the rational tree
    deep = foldl((t, _) -> _bc(:s, t), 1:20_000; init=Y)    # deep, not recursive
    @test pl_unify!(ld, _bv(4), deep)
    @test nchildren(resolve_term(ld, _bv(4))) == 2
end

# Upstream binds by overwriting a cell — no allocation at all. Here a binding is a store entry and a
# trail push into capacity reused from earlier attempts, so a WARM attempt allocates nothing; the
# identity maps (cyclic links) rehash after enough deletions, so an occasional attempt does
# (measured: ~1 in 6 attempts on a 2047-compound tree, 82 KB). A per-binding allocation would make
# EVERY attempt allocate — that is what this guards.
@testset "a warm attempt allocates nothing, but for periodic rehashes" begin
    ld = PL_local_data{_BT}()
    g1, g2 = _btree(10, () -> _bs(:a)), _btree(10, () -> _bs(:a))
    v1, v2 = _btree(10, _bfresh), _btree(10, _bfresh)
    for (a, b) in ((g1, g2), (v1, g1), (v1, v2))
        _battempt!(ld, a, b)
        _battempt!(ld, a, b)
        allocs = [@allocated(_battempt!(ld, a, b)) for _ in 1:60]
        @test count(==(0), allocs) >= 40
        @test _battempt!(ld, a, b)
    end
    @test isempty(ld.trail) && isempty(ld.bindings)
end
