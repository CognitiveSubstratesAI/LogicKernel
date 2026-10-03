# ORIGINAL: the term-interface conformance suite; Prolog has no term interface.
# test/core_lang/term_interface_testlib.jl — THE term-interface conformance suite, as a library.
#
# Not run on its own (no `test_` prefix). `test_term_interface.jl` runs it against the reference
# type; any other implementation of the interface runs it from its own tests:
#
#     include(joinpath(pkgdir(LogicKernel), "test", "core_lang", "term_interface_testlib.jl"))
#     TermConformance.run_term_conformance(MyTerm; mksym = …, mkgnd = …, label = "MyTerm")
#
# Every property here is GENERIC — stated through the interface, never through one type's fields.
# Where a property needs an outside judge, the judge is the HOST VALUE the term was built from (for
# identity) or SWI-Prolog's documented order (for the ladder) — never the implementation under test.
#
# ⏳ NOT YET HERE, deliberately not a placeholder test (an empty or skipped testset would fail the
# inert-testset guard, and should): the canonical-encoding property — the kernel's variant key of a
# term equals MORK's De Bruijn bytes for it. It arrives with `src/unify` (variant canonicalisation)
# and the PathMap extension; see docs/architecture.md.
module TermConformance

using Test, LogicKernel

"""
A grounded payload with its own `==` (equal modulo 10) and NO matching `hash` — the shape that
must key as a WILDCARD, never a bucket.
"""
struct CustomEq
    v::Int
end
Base.:(==)(a::CustomEq, b::CustomEq) = a.v % 10 == b.v % 10

"Host values every implementation's `mkgnd` must accept."
const HOST_VALUES = (
    0, 1, 2, big(2), -5, 0.0, -0.0, 1.0, 1.5, NaN, Inf, -Inf, 1.0f0, 1 // 2, "", "a", "ab",
    "b",
    true, 'c',
    [0.0], [-0.0], (0.0, 1), (-0.0, 1), 0.0 + 0.0im, 0.0 - 0.0im, missing, CustomEq(3),
    CustomEq(13)
)

"""
Identity of two host values, SWI-Prolog's: integers by value (SWI has one integer type, so `2` and
`big(2)` are identical); otherwise the same type and `isequal` — for IEEE floats, the same bits.
"""
host_identical(x, y)::Bool =
    if x isa Integer && !(x isa Bool) && y isa Integer && !(y isa Bool)
        x == y
    else
        typeof(x) === typeof(y) && (x isa Base.IEEEFloat ? x === y : isequal(x, y))
    end

"Groundness recomputed by the suite itself — the judge for `is_ground`, independent of the type."
_ground(t)::Bool =
    if kind(t) === VAR
        false
    elseif kind(t) !== EXPR
        true
    else
        all(i -> _ground(child(t, i)), 1:nchildren(t))
    end

"""
    run_term_conformance(T; mksym, mkgnd, label, gnd_judge = host_identical)

Run the whole conformance suite against the term type `T`. `mksym(name::Symbol)` must build a
[`SYM`](@ref) term and `mkgnd(v)` a [`GND`](@ref) term for every value in `HOST_VALUES`.
`gnd_judge(x, y)` states, on the HOST values, when the implementation's [`gnd_equal`](@ref) must
match: SWI's identity by default (the reference type); an implementation that matches by `==`
(Core's MeTTa terms) passes `(x, y) -> (x == y) === true`.
"""
function run_term_conformance(
    ::Type{T}; mksym, mkgnd, label::String, gnd_judge=host_identical
) where {T}
    sy(n) = mksym(n)::T
    gn(v) = mkgnd(v)::T
    ex(xs::T...) = mk_expr(T, T[xs...])
    @testset "term conformance: $label" begin
        @testset "constructors and accessors round-trip" begin
            for k in UInt64[0, 1, 42, typemax(UInt64)]
                v = mk_var(T, k)
                @test kind(v) === VAR
                @test var_key(v) == k
                @test nchildren(v) == 0
            end
            @test var_key(mk_var(T, UInt64(7))) == var_key(mk_var(T, UInt64(7)))
            @test var_key(mk_var(T, UInt64(7))) != var_key(mk_var(T, UInt64(8)))
            a, b, one = sy(:a), sy(:b), gn(1)
            e = ex(a, b, one)
            @test kind(e) === EXPR && nchildren(e) == 3
            @test compareStandard(child(e, 1), a) == 0
            @test compareStandard(child(e, 2), b) == 0
            @test compareStandard(child(e, 3), one) == 0
            vh = ex(mk_var(T, UInt64(9)), a)                      # a VARIABLE head
            @test kind(child(vh, 1)) === VAR && var_key(child(vh, 1)) == 9
            ch = ex(ex(sy(:curry), sy(:f)), sy(:x))               # a COMPOUND head
            @test kind(child(ch, 1)) === EXPR && nchildren(child(ch, 1)) == 2
            empty = mk_expr(T, T[])                               # the empty expression ()
            @test kind(empty) === EXPR && nchildren(empty) == 0
            @test nchildren(a) == 0 && nchildren(one) == 0
        end

        @testset "kind is correct for every constructor" begin
            @test kind(sy(:s)) === SYM
            @test all(v -> kind(gn(v)) === GND, HOST_VALUES)
            @test kind(mk_var(T, UInt64(1))) === VAR
            @test kind(ex(sy(:f))) === EXPR
        end

        # The kernel builds its containers and terms with `term_type(t)`, never `typeof(t)` — for an
        # abstract hierarchy those differ, and a leaf there breaks the kernel's walks (2026-10-03).
        @testset "term_type is the term type of every term, children included" begin
            v = mk_var(T, UInt64(1))
            e = ex(sy(:f), v, gn(1), ex(sy(:g), gn("s")))
            ts = T[v, sy(:s), e, mk_expr(T, T[]), (gn(x) for x in HOST_VALUES)...]
            append!(ts, (child(e, i) for i in 1:nchildren(e)))
            @test all(t -> term_type(t) === T, ts)
            @test length(ts) == length(HOST_VALUES) + 8
        end

        # The kernel's "same term" test is `===` (upstream: a cell address) and its identity maps
        # key by it, so `===` on compounds must be an address compare. A compound that is a plain
        # immutable value makes it structural — exponential on shared subterms (2026-10-03).
        @testset "a compound has object identity: separately built twins are not ===" begin
            mk() = ex(sy(:f), gn(1), ex(sy(:g), mk_var(T, UInt64(1))))
            a, b = mk(), mk()
            @test compareStandard(a, b) == 0              # identical terms…
            @test a !== b                                 # …but two compounds
            @test mk_expr(T, T[]) !== mk_expr(T, T[])
            @test a === a && child(a, 3) === child(a, 3)  # a compound is itself
        end

        @testset "sym_key is equal exactly when the symbols are equal" begin
            names = (:a, :b, :ab, :f, :foo, Symbol("a b"), :α, Symbol(""))
            @test all(n -> sym_key(sy(n)) == sym_key(sy(n)), names)     # separately built twins
            for (i, m) in enumerate(names), (j, n) in enumerate(names)
                i < j && @test sym_key(sy(m)) != sym_key(sy(n))
            end
        end

        @testset "sym_hash is equal for the same symbol" begin
            names = (:a, :b, :ab, :f, :foo, Symbol("a b"), :α, Symbol(""))
            @test all(n -> sym_hash(sy(n)) == sym_hash(sy(n)), names)   # separately built twins
            @test all(n -> sym_hash(sy(n)) isa UInt64, names)
            # distinct symbols MAY collide: no distinctness law (identity is sym_key)
        end

        @testset "gnd_equal follows the implementation's judge; gnd_key follows gnd_equal" begin
            # Every pair of host values: `gnd_equal` is a strict Bool, agrees with the judge, and
            # two matching values never key apart (THE LAW — a key that splits them drops answers).
            ok_bool = ok_judge = ok_law = true
            matches = 0
            for x in HOST_VALUES, y in HOST_VALUES
                r = gnd_equal(gn(x), gn(y))
                ok_bool &= r isa Bool
                ok_judge &= r === gnd_judge(x, y)
                matches += r === true
                kx, ky = gnd_key(gn(x)), gnd_key(gn(y))
                r === true && kx !== nothing && ky !== nothing && (ok_law &= kx == ky)
            end
            @test ok_bool
            @test ok_judge
            @test ok_law
            @test matches > length(HOST_VALUES)       # the judge matched distinct values too
        end

        @testset "is_ground matches a full recomputation" begin
            v = mk_var(T, UInt64(1))
            ts = (sy(:a), gn(1), v, ex(), ex(sy(:f), sy(:a)), ex(sy(:f), v),
                ex(ex(sy(:g), v), sy(:a)),
                ex(sy(:f), ex(sy(:g), ex(sy(:h), gn(2.5)))), ex(v), ex(ex(ex(v))))
            @test all(t -> is_ground(t) == _ground(t), ts)
            @test all(t -> is_ground_walk(t) == _ground(t), ts)
            @test count(is_ground, ts) == 5                       # the judge itself is not vacuous
        end

        @testset "standard order: total, consistent with identity, SWI-Prolog's ladder" begin
            c(a, b) = compareStandard(a, b)
            # every sample carries an ID; two samples are identical exactly when their IDs match.
            # Atomic IDs come from the host values (`host_identical`), so the judge is not the
            # implementation; twins are built SEPARATELY and must still compare 0.
            samples = Tuple{T, Int}[]
            for (i, v) in enumerate(HOST_VALUES)
                id = something(findfirst(w -> host_identical(v, w), HOST_VALUES), i)
                push!(samples, (gn(v), id))
            end
            n0 = length(HOST_VALUES)
            for (k, s) in enumerate((:a, :ab, :b, :f, :g, :α, Symbol("")))
                push!(samples, (sy(s), n0 + k), (sy(s), n0 + k))
            end
            n1 = n0 + 10
            for k in 1:3
                push!(
                    samples, (mk_var(T, UInt64(k)), n1 + k), (mk_var(T, UInt64(k)), n1 + k)
                )
            end
            mkx = (() -> ex(sy(:f), sy(:a)), () -> ex(sy(:f), sy(:b)),
                () -> ex(sy(:g), sy(:a)),
                () -> ex(sy(:f), sy(:a), sy(:b)), () -> ex(sy(:f), gn(1)),
                () -> ex(sy(:f), gn(1.0)),
                () -> ex(mk_var(T, UInt64(1)), sy(:a)),
                () -> ex(ex(sy(:curry), sy(:f)), sy(:x)),
                () -> ex(), () -> ex(sy(:h), ex(sy(:g), ex(sy(:f), gn(0.0)))),
                # arities NESTED: a walk whose agenda is typed by the outer compound breaks here
                () -> ex(sy(:f), ex(sy(:g), sy(:a)), ex(sy(:h), sy(:a), sy(:b))),
                () -> ex(sy(:h), ex(sy(:g), ex(sy(:f), gn(-0.0)))))
            n2 = n1 + 10
            for (k, mk) in enumerate(mkx)
                push!(samples, (mk(), n2 + k), (mk(), n2 + k))
            end
            antisym = identity_ok = eqmode_ok = true
            for (a, ia) in samples, (b, ib) in samples
                r = c(a, b)
                antisym &= r in (-1, 0, 1) && r == -c(b, a)
                identity_ok &= (r == 0) == (ia == ib)
                e = compareStandard(a, b, true)
                eqmode_ok &= (r == 0) ? e == 0 : e == LogicKernel.CMP_NOTEQ
            end
            @test antisym
            @test identity_ok
            @test eqmode_ok
            trans = 0
            for (a, _) in samples, (b, _) in samples
                c(a, b) <= 0 || continue
                for (d, _) in samples
                    c(b, d) <= 0 && c(a, d) > 0 && (trans += 1)
                end
            end
            @test trans == 0
            @test length(samples) > 60                            # the checks above saw real data

            # SWI-Prolog's ladder (pl-prims.c / pl-data.h): Var < Number < String < Atom < Compound
            lt(a, b) = c(a, b) == -1
            @test lt(mk_var(T, UInt64(5)), gn(-5))
            @test lt(gn(10^6), gn("")) && lt(gn("zz"), sy(:a)) && lt(sy(:zz), ex(sy(:a)))
            @test lt(mk_var(T, UInt64(1)), mk_var(T, UInt64(2)))
            @test lt(gn(1.0), gn(1))                              # equal value: the FLOAT first
            @test lt(gn(1), gn(1.5)) && lt(gn(1.5), gn(2))        # numbers by value, mixed types
            @test lt(gn(NaN), gn(-Inf)) && lt(gn(-0.0), gn(0.0))
            @test lt(sy(:a), sy(:ab)) && lt(sy(:ab), sy(:b))      # atoms by character codes
            @test lt(gn("a"), gn("ab")) && lt(gn("ab"), gn("b"))
            @test lt(ex(sy(:z), sy(:z)), ex(sy(:a), sy(:a), sy(:a)))   # compounds: ARITY first
            @test lt(ex(sy(:f), sy(:a)), ex(sy(:f), sy(:b))) &&
                lt(ex(sy(:f), sy(:b)), ex(sy(:g), sy(:a)))
        end
    end
end

end # module TermConformance
