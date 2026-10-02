# UPSTREAM: swipl-devel tests/db/test_jit.pl @ bae881a24a3f
# CLASS: code
# COPYRIGHT: Copyright (c)  2011-2025, University of Amsterdam
# COPYRIGHT: VU University Amsterdam
# COPYRIGHT: SWI-Prolog Solutions b.v.
#
# SWI-Prolog's own tests of just-in-time indexing, unit by unit (plunit `jit` and `jit_static`),
# run on the kernel's port of pl-index.c through test/db/index_testlib.jl.
#
# NOT PORTED YET — they need retract/1, retractall/1, clause/2 and clause garbage collection (the
# `db` subsystem): the second `remove` unit, `retract`, `retract2`, `clause`.
#
# `cleanup(retractall(d(_,_)))` and the `retractall(d(_,_))` that opens test_index_1/2 are not
# needed: each unit builds its own `d/2` (retract is not ported), which is the state those
# retractalls leave behind as far as the units observe it — `has_hashes` passes in SWI only once
# the previous unit's index is gone.
include(joinpath(@__DIR__, "index_testlib.jl"))

const _J = DefaultTerm
_js(n) = sym_term(_J, Symbol(n))
_jg(v) = gnd_term(_J, v)
_je(f, xs...) = mk_expr(_J, _J[_js(f), xs...])
let n = UInt64(0)
    global _jv() = mk_var(_J, n += 1)
end

# PORT: test_jit.pl has_hashes
"`has_hashes(P, Hashes)`: P has exactly single-argument hashes on the arguments in `Hashes`."
function has_hashes(p::IxPred, hashes::Vector{Int})::Bool
    indexed = LK.unify_index_pattern(p.def)
    indexed === nothing && return false             # predicate_property(P, indexed(Indexed))
    args = Int[]
    for d in indexed
        hash_arg(d, args) || return false           # maplist(hash_arg, Indexed, Args)
    end
    return sort(unique(args)) == sort(unique(hashes))   # sort/2 also removes duplicates
end

# PORT: test_jit.pl hash_arg
"`hash_arg(Dict, Arg) :- [Arg] = Dict.arguments.`"
function hash_arg(d::LK.index_property, args::Vector{Int})::Bool
    length(d.arguments) == 1 || return false
    push!(args, d.arguments[1])
    return true
end

# PORT: test_jit.pl not_hashed
"`not_hashed(P) :- \\+ predicate_property(P, indexed(_)).`"
not_hashed(p::IxPred)::Bool = LK.unify_index_pattern(p.def) === nothing

# PORT: test_jit.pl mkbigint
"`mkbigint(Shift, I, Big) :- Big is 1<<Shift+I.`"
mkbigint(shift::Int, i::Int)::Integer =
    shift >= 63 ? (BigInt(1) << shift) + i : (1 << shift) + i

# PORT: test_jit.pl mkfloat
"`mkfloat(I, Float) :- Float is float(I).`"
mkfloat(i::Int)::Float64 = Float64(i)

# PORT: test_jit.pl test_index_1
"""
`test_index_1(Convert)`: 1000 clauses `d(D, I)`; looking each `D` up finds its `I`, and the
predicate has exactly a hash on argument 1. `T` is the term type holding `D` and `I`.
"""
function test_index_1(::Type{T}, convert, int)::Nothing where {T}
    g(v) = gnd_term(T, v)
    d = ix_pred(T, :d, 2; dynamic=true)
    for i in 1:1000
        ix_assertz!(d, mk_expr(T, T[sym_term(T, :d), g(convert(i)), g(int(i))]))
    end
    for i in 1:1000
        ans = ix_call(
            d, mk_expr(T, T[sym_term(T, :d), g(convert(i)), mk_var(T, UInt64(1))])
        )
        @test any(a -> child(a[1], 3) == g(int(i)), ans)    # assertion((d(D, I2), I2 == I))
    end
    @test has_hashes(d, [1])
    return nothing
end

# PORT: test_jit.pl test_index_2
"`test_index_2(Convert)`: as `test_index_1` with the arguments swapped — a hash on argument 2."
function test_index_2(::Type{T}, convert, int)::Nothing where {T}
    g(v) = gnd_term(T, v)
    d = ix_pred(T, :d, 2; dynamic=true)
    for i in 1:1000
        ix_assertz!(d, mk_expr(T, T[sym_term(T, :d), g(int(i)), g(convert(i))]))
    end
    for i in 1:1000
        ans = ix_call(
            d, mk_expr(T, T[sym_term(T, :d), mk_var(T, UInt64(1)), g(convert(i))])
        )
        @test any(a -> child(a[1], 2) == g(int(i)), ans)    # assertion((d(I2, D), I2 == I))
    end
    @test has_hashes(d, [2])
    return nothing
end

"The term type for the `bigint` units: `1<<100+I` needs an unbounded integer."
const _JBig = Term{BigInt}

@testset "jit" begin
    # PORT: test_jit.pl remove
    @testset "remove" begin
        d = ix_pred(_J, :d, 2; dynamic=true)
        for x in 1:50
            ix_assertz!(d, _je(:d, _jg(x), _jg(x)))
        end
        @test !isempty(ix_call(d, _je(:d, _jv(), _jg(30))))        # d(_,30)
        @test has_hashes(d, [2])
        for x in 51:125
            ix_assertz!(d, _je(:d, _jg(x), _jg(x)))
        end
        @test not_hashed(ix_pred(_J, :p, 2))                       # not_hashed(p(_,_))
        @test !isempty(ix_call(d, _je(:d, _jg(30), _jv())))        # d(30,_)
        @test has_hashes(d, [1])
    end
    # PORT: test_jit.pl string
    @testset "string" begin
        test_index_1(_J, i -> "a" * string(i), identity)           # string_concat("a")
    end
    # PORT: test_jit.pl bigint
    @testset "bigint" begin
        test_index_1(_JBig, i -> BigInt(mkbigint(100, i)), BigInt)
    end
    # PORT: test_jit.pl midint
    @testset "midint" begin
        test_index_1(_J, i -> Int(mkbigint(60, i)), identity)
    end
    # PORT: test_jit.pl float
    @testset "float" begin
        test_index_1(_J, mkfloat, identity)
    end
    # PORT: test_jit.pl string
    @testset "string" begin
        test_index_2(_J, i -> "a" * string(i), identity)
    end
    # PORT: test_jit.pl bigint
    @testset "bigint" begin
        test_index_2(_JBig, i -> BigInt(mkbigint(100, i)), BigInt)
    end
    # PORT: test_jit.pl midint
    @testset "midint" begin
        test_index_2(_J, i -> Int(mkbigint(60, i)), identity)
    end
    # PORT: test_jit.pl float
    @testset "float" begin
        test_index_2(_J, mkfloat, identity)
    end
    # p1/1 and p2/1: compounds nested 7 and 8 deep, two clauses each (static)
    nest(fs, leaf) = foldr((f, t) -> _je(f, t), fs; init=leaf)
    p1 = ix_pred(_J, :p1, 1)
    p2 = ix_pred(_J, :p2, 1)
    for k in 1:2
        ix_assertz!(p1, _je(:p1, nest((:a, :b, :c, :d, :e, :f, :g), _jg(k))))
        ix_assertz!(p2, _je(:p2, nest((:a, :b, :c, :d, :e, :f, :g, :h), _jg(k))))
    end
    # PORT: test_jit.pl depth
    @testset "depth" begin
        @test !isempty(ix_call(p1, _je(:p1, nest((:a, :b, :c, :d, :e, :f, :g), _jg(1)))))
        @test !isempty(ix_call(p1, _je(:p1, nest((:a, :b, :c, :d, :e, :f, :g), _jg(2)))))
    end
    # PORT: test_jit.pl depth_exceeded
    @testset "depth_exceeded" begin
        @test !isempty(
            ix_call(p2, _je(:p2, nest((:a, :b, :c, :d, :e, :f, :g, :h), _jg(1))))
        )
        @test !isempty(
            ix_call(p2, _je(:p2, nest((:a, :b, :c, :d, :e, :f, :g, :h), _jg(2))))
        )
    end
end

@testset "jit_static" begin
    nil, cons = _js(Symbol("[]")), (h, t) -> _je(Symbol("[|]"), h, t)
    x = ix_pred(_J, :x, 5)
    ix_assertz!(x, _je(:x, _js(:x), _js(:x), _js(:x), _js(:x), nil))
    ix_assertz!(x, _je(:x, _js(:x), _js(:x), _js(:x), _js(:x), cons(_jv(), _jv())))
    a = ix_pred(_J, :a, 5)
    ix_assertz!(a, _je(:a, _jv(), _jv(), _jv(), _jv(), nil))
    ix_assertz!(a, _je(:a, _jv(), _jv(), _jv(), _jv(), cons(_jv(), _jv())))
    m = ix_pred(_J, :m, 5)                          # :- mode(m(?,?,?,?,-)).
    m.def.impl_clauses.args[5].meta = LK.MA_VAR
    ix_assertz!(m, _je(:m, _jv(), _jv(), _jv(), _jv(), nil))
    ix_assertz!(m, _je(:m, _jv(), _jv(), _jv(), _jv(), cons(_jv(), _jv())))
    b = ix_pred(_J, :b, 5)
    ix_assertz!(b, _je(:b, _jv(), _jv(), _jv(), _jv(), nil))
    ix_assertz!(b, _je(:b, _jv(), _jv(), _jv(), cons(_jv(), _jv()), _jv()))
    pa = ix_pred(_J, :pa, 2)
    ix_assertz!(pa, _je(:pa, _jv(), _jv()))
    ix_assertz!(pa, _je(:pa, _jv(), _js(:x)))
    ix1386 = ix_pred(_J, :ix1386, 2)
    ix_assertz!(ix1386, _je(:ix1386, _js(:real), _je(:',', _jg(-1.0e16), _jg(1.0e16))))
    ix_assertz!(ix1386, _je(:ix1386, _js(:boolean), _je(:',', _jg(0), _jg(1))))

    # PORT: test_jit.pl x
    @testset "x" begin                              # must use S_LIST
        @test !isempty(ix_call(x, _je(:x, _jv(), _jv(), _jv(), _jv(), nil)))
    end
    # PORT: test_jit.pl a
    @testset "a" begin                              # must use S_LIST (test H_VOID_N)
        @test !isempty(ix_call(a, _je(:a, _jv(), _jv(), _jv(), _jv(), nil)))
    end
    # PORT: test_jit.pl b
    @testset "b" begin                              # may not use S_LIST (test H_VOID_N)
        ans = ix_call(b, _je(:b, _jv(), _jv(), _jv(), _jv(), nil))
        @test !isempty(ans) && !ans[1][2]           # call_cleanup(..., Det=true), var(Det)
    end
    # PORT: test_jit.pl m
    @testset "m" begin                              # may not use S_LIST (test mode/1)
        ans = ix_call(m, _je(:m, _jv(), _jv(), _jv(), _jv(), nil))
        @test !isempty(ans) && !ans[1][2]
    end
    # PORT: test_jit.pl pa
    @testset "pa" begin                             # primary index should be on arg 2
        @test !isempty(ix_call(pa, _je(:pa, _jv(), _js(:y))))
        @test ix_primary_index(pa) == 2             # what swipl 10.1.16 reports for pa/2
    end
    # PORT: test_jit.pl ix1386
    @testset "ix1386" begin                         # Issue #1386: primary must win over a
        ans = ix_call(ix1386, _je(:ix1386, _js(:real), _je(:',', _jv(), _jv())))
        @test !isempty(ans) && ans[1][2]            # shallow-useless deep list index: Det == true
    end
end
