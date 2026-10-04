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
    0, 1, 2, big(2), big(2)^70, -big(2)^70, -5, 0.0, -0.0, 1.0, 1.5, NaN, Inf, -Inf, 1.0f0,
    big"1.5",          # a Real with no SWI type: OTHER, and ordered as other (the kind query rules)
    1 // 2,
    "", "a", "ab",
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

"""
Seconds `f(x...)` takes, the result kept alive. A bare `@elapsed(a === b)` measures NOTHING: `===`
has no side effects, so the compiler deletes the unused comparison — a timing guard written that
way passed with structural `===` (mutation-proved, 2026-10-03).
"""
@noinline function _timed(f, x...)::Float64
    t0 = time_ns()
    Base.donotdelete(f(x...))
    return (time_ns() - t0) / 1e9
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
        # key by it. THE RULE (user, 2026-10-03): `===` on compounds is CONSTANT-TIME, and
        # `a === b` implies the terms are identical; SHARED subterms are permitted — SWI's own
        # copy_term/2 shares ground subterms (pl-copyterm.c), so separately built twins MAY be one
        # object. A first statement, "twins are never ===", was too strong: it failed on the
        # sharing implementation (`AltTerm{true}`), at `()`. The implication over every pair of
        # samples is checked with the standard order below.
        @testset "=== on compounds is constant-time and implies identity; sharing permitted" begin
            # twins of a DAG, each level `g(x, x)`: a structural `===` or `objectid` walks every
            # path. The depths are MEASURED (2026-10-03) on immutable tuple-valued compounds: a
            # structural `===` grows ~4x a level (20 ms at depth 10, 6.5 s at 14 — at 24 it never
            # finished), a structural `objectid` ~2x (8.8 ms at 16); a mutable compound takes
            # microseconds at any depth. So each gets a depth that fails in well under a second.
            dag(d) =
                d == 0 ? ex(sy(:f), mk_var(T, UInt64(1))) : (x=dag(d - 1); ex(sy(:g), x, x))
            a, b = dag(11), dag(11)
            @test minimum(_timed(===, a, b) for _ in 1:5) < 1e-3
            @test minimum(_timed(objectid, dag(20)) for _ in 1:5) < 1e-3
            @test a === a && child(a, 2) === child(a, 3)  # a compound is itself; shared is shared
            # near misses a sharing key could merge: not identical, so never one object
            for (x, y) in ((1, 1.0), (0.0, -0.0), (1, 2), (NaN, -NaN), ("a", "b"))
                @test ex(sy(:f), gn(x)) !== ex(sy(:f), gn(y))
            end
            @test ex(sy(:f), sy(:a)) !== ex(sy(:f), gn("a"))
            # SWI-7's [] and the atom '[]': one name, two symbols — a key by name merges them
            @test ex(sy(:f), mk_nil(T)) !== ex(sy(:f), mk_sym(T, Symbol("[]")))
        end

        # ── the Prolog layer (Q1, user 2026-10-03) ─────────────────────────────────────────────
        @testset "mk_sym and mk_gnd build what the caller's constructors build" begin
            for n in (:a, :f, Symbol(""), Symbol("[]"), Symbol("[|]"), :α, :dict)
                s = mk_sym(T, n)::T
                @test kind(s) === SYM && !is_reserved_symbol(s) && !is_nil(s)
                @test compareStandard(s, sy(n)) == 0 && sym_key(s) == sym_key(sy(n))
            end
            @test all(
                v -> (g=mk_gnd(T, v)::T; kind(g) === GND && compareStandard(g, gn(v)) == 0),
                HOST_VALUES
            )
        end

        # SWI-7's `[]` (pl-ressymbol.c): a RESERVED SYMBOL — the atom tag with the blob type
        # `reserved_symbol`, distinct from the text atom `'[]'`; atomic, not an atom; ranked 0,
        # "between normal blob and text", so it sorts before EVERY text atom ('' included) —
        # probed in swipl 10.1.16. Two reserved symbols compare by strcmp of their names.
        @testset "reserved symbols: [] is not the atom '[]', and sorts before every atom" begin
            c(a, b) = compareStandard(a, b)
            nil, qnil = mk_nil(T)::T, mk_sym(T, Symbol("[]"))
            @test kind(nil) === SYM && is_reserved_symbol(nil) && is_nil(nil)
            @test !is_reserved_symbol(qnil) && !is_nil(qnil)
            @test sym_key(nil) != sym_key(qnil) && c(nil, qnil) != 0       # [] == '[]' fails
            @test sym_key(nil) == sym_key(mk_nil(T)) && c(nil, mk_nil(T)) == 0
            r = mk_reserved_symbol(T, Symbol("[]"))::T
            @test is_nil(r) && sym_key(r) == sym_key(nil)
            # the TEXT hash, as upstream's atom hash_value — term_hash([]) == term_hash('[]')
            @test sym_hash(nil) == sym_hash(qnil)
            d = mk_reserved_symbol(T, :dict)::T                 # pl-ressymbol.c retypes ATOM_dict
            @test is_reserved_symbol(d) && !is_nil(d) &&
                sym_key(d) != sym_key(mk_sym(T, :dict))
            for n in
                (Symbol(""), :a, Symbol("[]"), Symbol("[|]"), :dict, Symbol("\U0001D11E"))
                @test c(nil, mk_sym(T, n)) == -1 && c(mk_sym(T, n), nil) == 1
                @test c(d, mk_sym(T, n)) == -1
            end
            @test c(nil, d) == -1 && c(d, nil) == 1             # strcmp("[]", "dict") < 0
            @test c(gn("zz"), nil) == -1 && c(gn(1), nil) == -1 && c(gn(1.5), nil) == -1
            @test c(nil, ex(sy(:f), sy(:a))) == -1 && c(nil, mk_var(T, UInt64(1))) == 1
            @test !is_reserved_symbol(gn(1)) && !is_nil(gn(1)) && !is_nil(ex(sy(:f)))
            @test !is_nil(mk_var(T, UInt64(1)))
        end

        # SWI's list cell (pl-fli.c `PL_is_pair`; user, 2026-10-04): a compound whose head is the
        # TEXT atom '[|]' with exactly two arguments — `[H|T]` and '[|]'(H, T) are one term. Not:
        # another arity, a `[]` or `'[]'` head, a reserved '[|]', a non-symbol head (`$expr/n`).
        @testset "is_pair: a text '[|]' head with exactly two arguments" begin
            L = mk_sym(T, Symbol("[|]"))
            a, b = sy(:a), sy(:b)
            pair = ex(L, a, b)                                  # '[|]'(a, b): [a|b]
            @test is_pair(pair) && is_pair(ex(sy(Symbol("[|]")), a, b))
            @test is_pair(ex(L, gn(1), mk_nil(T)))              # [1]
            lst = ex(L, a, ex(L, b, mk_nil(T)))                 # [a, b]
            @test is_pair(lst) && is_pair(child(lst, 3)) &&
                !is_pair(child(child(lst, 3), 3))
            @test is_pair(ex(L, mk_var(T, UInt64(1)), mk_var(T, UInt64(2))))      # [X|Y]
            @test !is_pair(ex(L)) && !is_pair(ex(L, a)) && !is_pair(ex(L, a, b, a))
            @test !is_pair(ex(mk_nil(T), a, b)) && !is_pair(ex(sy(Symbol("[]")), a, b))
            @test !is_pair(ex(mk_reserved_symbol(T, Symbol("[|]")), a, b))       # not TEXT
            @test !is_pair(ex(sy(:f), a, b)) && !is_pair(ex(sy(Symbol(".")), a, b))
            for h in (mk_var(T, UInt64(1)), gn(1), pair, ex())  # `$expr/3`: two after the head
                @test !is_pair(ex(h, a, b))
            end
            @test !is_pair(L) && !is_pair(mk_nil(T)) && !is_pair(gn(1)) &&
                !is_pair(mk_var(T, UInt64(1))) && !is_pair(ex())
        end

        # SWI's numbers by SEMANTIC kind — integer of any size, rational, float — with one typed
        # getter per representation (user, 2026-10-03): branch once on the kind, then stay
        # type-stable. Small vs big integer is storage: a HEAD integer is `H_SMALLINT` when tagged,
        # else `H_MPZ` (pl-comp.c, probed); `is_portable_smallint` is body arithmetic's.
        # SWI keeps rationals CANONICAL: `2r1` IS the integer 2 (user, 2026-10-04). swipl 10.1.16,
        # probed with prefer_rationals=false (its default): `2r1 == 2`, `integer(2r1)`,
        # `compare(=, 2r1, 2)`, term_hash and variant_sha1 equal; `-3r1` is `-3`. So `mk_gnd`
        # normalises once, and identity, order and hashing agree by construction.
        @testset "a rational with denominator 1 IS the integer (SWI's canonical form)" begin
            for (r, i) in (
                (2 // 1, 2),
                (-3 // 1, -3),
                (0 // 1, 0),
                (typemax(Int64) // 1, typemax(Int64))
            )
                q, n = gn(r), gn(i)
                @test number_kind(q) === NUM_INTEGER && integer_is_int64(q)
                @test int64_value(q) === Int64(i)
                @test compareStandard(q, n) == 0 && compareStandard(q, n, true) == 0  # 2r1 == 2
                @test gnd_key(q) == gnd_key(n)
                @test LogicKernel.pl_term_hash(q) == LogicKernel.pl_term_hash(n)    # term_hash
                @test LogicKernel.pl_variant_sha1(q) == LogicKernel.pl_variant_sha1(n)
                @test LogicKernel.is_variant_ptr(q, n)
            end
            # beyond Int64: `big(2)^70 // 1` is the BigInt integer; and a BigInt-typed `5 // 1` is 5
            for (r, i) in
                ((Rational{BigInt}(big(2)^70, 1), big(2)^70), (Rational{BigInt}(5, 1), 5))
                q, n = gn(r), gn(i)
                @test number_kind(q) === NUM_INTEGER && bigint_value(q) == i
                @test integer_is_int64(q) == (typemin(Int64) <= i <= typemax(Int64))
                @test compareStandard(q, n) == 0 && gnd_key(q) == gnd_key(n)
                @test LogicKernel.pl_variant_sha1(q) == LogicKernel.pl_variant_sha1(n)
                @test LogicKernel.is_variant_ptr(q, n)
            end
            @test number_kind(gn(1 // 2)) === NUM_RATIONAL        # a true rational stays one
            @test compareStandard(gn(1 // 2), gn(2 // 4)) == 0     # and reduced: 1r2 == 2r4
        end

        # the kind query is the ONE place for a grounded value's Prolog type: the standard order's
        # classes follow it — numbers < strings < atoms < other grounded values < compounds
        @testset "the standard order's class follows the kind query" begin
            class(t) =
                if kind(t) === SYM
                    3
                else
                    k = number_kind(t)
                    if k in (NUM_INTEGER, NUM_RATIONAL, NUM_FLOAT)
                        1
                    elseif k === NUM_STRING
                        2
                    else
                        4
                    end
                end
            ts = T[(gn(v) for v in HOST_VALUES)...; sy(:a); sy(:zz)]
            for x in ts, y in ts
                class(x) < class(y) && @test compareStandard(x, y) == -1
            end
            @test any(t -> class(t) == 4, ts) && any(t -> class(t) == 2, ts)
        end

        @testset "numbers: the kind, and a typed getter per kind" begin
            seen = Set{NumKind}()
            for v in HOST_VALUES
                g = gn(v)
                k = number_kind(g)
                push!(seen, k)
                if v isa Integer && !(v isa Bool)
                    @test k === NUM_INTEGER
                    b = bigint_value(g)
                    @test b isa BigInt && b == v
                    fits = typemin(Int64) <= v <= typemax(Int64)
                    @test integer_is_int64(g) == fits
                    if fits
                        @test int64_value(g) === Int64(v)
                    else
                        @test_throws InexactError int64_value(g)
                    end
                elseif v isa Rational
                    q = rational_value(g)
                    @test k === NUM_RATIONAL && q isa Rational{BigInt} && q == v
                elseif v isa Base.IEEEFloat
                    @test k === NUM_FLOAT && float_value(g) === Float64(v)  # bits: -0.0, NaN
                elseif v isa AbstractString                 # SWI's TAG_STRING (user, 2026-10-04)
                    @test k === NUM_STRING && string_value(g) == v &&
                        string_value(g) isa String
                else
                    @test k === NUM_OTHER                   # grounded, no SWI type
                end
            end
            @test seen == Set((NUM_INTEGER, NUM_RATIONAL, NUM_FLOAT, NUM_STRING, NUM_OTHER))
            @test_throws ArgumentError string_value(gn(1))
            @test_throws ArgumentError string_value(sy(:a))
            @test all(
                t -> number_kind(t) === NUM_NONE,
                (sy(:a), mk_nil(T), mk_var(T, UInt64(1)), ex(sy(:f), gn(1)), ex())
            )
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
            antisym = identity_ok = eqmode_ok = egal_ok = true
            for (a, ia) in samples, (b, ib) in samples
                r = c(a, b)
                antisym &= r in (-1, 0, 1) && r == -c(b, a)
                identity_ok &= (r == 0) == (ia == ib)
                egal_ok &= a !== b || r == 0                      # `===` implies identical
                e = compareStandard(a, b, true)
                eqmode_ok &= (r == 0) ? e == 0 : e == LogicKernel.CMP_NOTEQ
            end
            @test antisym
            @test identity_ok
            @test egal_ok
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
