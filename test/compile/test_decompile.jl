# ORIGINAL: the head decompiler over the clause's literal table (V1 L2); swipl has no test that decompiles a head and checks each literal's kind.
# test/compile/test_decompile.jl — decompiling a clause head from its CODE and LITERAL TABLE (V1 L2;
# user, 2026-10-04: "decompiling reconstructs exactly the literal stored, including its kind (so `1`
# and `1.0`, or `[]` and `'[]'`, never collapse), with conformance cases on all three
# implementations"). TERM-GENERIC: runtests.jl runs it on every implementation.
#   * every literal comes back as the very term the clause held — same kind, value and host type —
#     so pairs that are equal under Julia's `==` (`1`/`1.0`, `-0.0`/`0.0`, `true`/`1`) or in text
#     (`[]`/`'[]'`, `"abc"`/`abc`) stay apart;
#   * a random head comes back as a VARIANT of itself (`=@=`): voids, shared variables, lists,
#     `$expr/n` and every kind of literal;
#   * the code reads its table consistently: every literal operand indexes it, each literal once,
#     and `argKey` gives every argument the key `indexOfWord` gives the term;
#   * a grounded value SWI has no type for (NUM_OTHER) is an OPAQUE literal: `H_ATOM`, its literal
#     the value itself, matched by `gnd_equal` (DIVERGES — SWI has no such case; src/pl-comp.jl § the
#     literal table).
include(joinpath(@__DIR__, "..", "db", "index_testlib.jl"))
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
using Random

const _D = lk_term_type(
    Union{Int64, Float64, String, BigInt, Rational{BigInt}, Bool, Vector{Float64}}
)
"The database the fresh predicates of this file are compiled in (its global data)."
const _DGD = LK.PL_global_data{_D}()
_ds(n) = lk_sym(_D, Symbol(n))
_dg(v) = lk_gnd(_D, v)
_de(f, xs::_D...) = mk_expr(_D, _D[_ds(f), xs...])
_dv(k::Int) = lk_var(_D, UInt64(k))
_dcons(h::_D, t::_D) = mk_expr(_D, _D[_ds("[|]"), h, t])

"`head` compiled as a clause of its predicate in this file's database (never asserted)."
function _dclause(head::_D)::LK.Clause{_D}
    user = LK.MODULE_user(_DGD)
    proc = LK.lookupProcedure(child(head, 1), nchildren(head) - 1, user)
    return LK.compileClause(_DGD, head, nothing, proc, user)
end

"Compile `head`, then decompile it into `name(_, …, _)`: the head the code describes."
function _ddecompile(head::_D)::_D
    cl = _dclause(head)
    n = nchildren(head) - 1
    goal = mk_expr(_D, _D[child(head, 1); [_dv(900_000 + i) for i in 1:n]])
    ld = LK.PL_local_data{_D}()
    LK.decompileHead!(ld, cl, goal) || error("decompileHead! failed on a fresh goal")
    return LK.resolve_term(ld, goal)
end

"The same literal to SWI: kind, identity (`sym_key`, `gnd_equal`) and number kind."
function _dident(a::_D, b::_D)::Bool
    kind(a) === kind(b) || return false
    kind(a) === SYM && return sym_key(a) == sym_key(b)
    kind(a) === GND || return false
    return number_kind(a) === number_kind(b) && gnd_equal(a, b)
end
"""
The very literal: SWI's identity AND the host type. A head may hold a term built elsewhere —
`AltTerm{true}` shares a ground compound with an identical one built earlier, so `[2^56]` may hold
a `BigInt` 2^56 — so exactness is checked against the HEAD's term, identity against the value.
"""
_dsame(a::_D, b::_D)::Bool =
    _dident(a, b) && (kind(a) !== GND || typeof(lk_value(a)) === typeof(lk_value(b)))

"A random head argument: variables (shared and singleton), literals of every kind, compounds, lists, `\$expr/n`."
function _darg(rng::AbstractRNG, shared::AbstractVector, depth::Int)::_D
    r = rand(rng)
    r < 0.15 && return _dv(rand(rng, 1:(1 << 40)))                     # almost surely a void
    r < 0.3 && return rand(rng, shared)
    if r < 0.6
        return rand(
            rng,
            (
                _ds(:a), _ds("[]"), mk_nil(_D), _ds("it's"), _dg(1), _dg(1.0), _dg(-0.0),
                _dg(0.0), _dg(2^56), _dg(big(2)^70), _dg(Rational{BigInt}(1 // 3)),
                _dg("abc"), _dg(""), _dg(true), _dg([1.0, 2.0])
            )
        )
    end
    depth >= 3 && return _ds(:z)
    kids = [_darg(rng, shared, depth + 1) for _ in 1:rand(rng, 0:3)]
    r2 = rand(rng)
    r2 < 0.5 && return _de(rand(rng, (:f, :g)), kids...)
    r2 < 0.8 && return foldr(
        _dcons, kids; init=rand(rng) < 0.5 ? mk_nil(_D) : _darg(rng, shared, 3)
    )
    return mk_expr(_D, _D[_darg(rng, shared, 3); kids])                 # often `$expr/n`
end

"The literal indices the code of `cl` refers to, in code order."
function _dliteral_refs(cl::LK.Clause{_D})::Vector{Int}
    refs = Int[]
    pc = LK.Code(cl, 1)
    while pc.pc <= length(cl.codes)
        c = LK.decode(pc)
        w = pc.pc < length(cl.codes) ? cl.codes[pc.pc + 1] : UInt64(0)
        if c == LK.H_FUNCTOR || c == LK.H_RFUNCTOR
            LK.functor_literal(w) == 0 || push!(refs, LK.functor_literal(w))
        elseif c in (LK.H_ATOM, LK.H_SMALLINT, LK.H_MPZ, LK.H_MPQ, LK.H_FLOAT, LK.H_STRING)
            push!(refs, Int(w))
        end
        pc = LK.stepPC(pc)
    end
    return refs
end

@testset "decompiling a head from its literal table" begin
    @testset "each literal comes back exactly, its kind included" begin
        # pairs equal under Julia's `==` or in text, which must stay apart
        pairs = [
            (_dg(1), _dg(1.0)), (mk_nil(_D), _ds("[]")), (_dg("abc"), _ds(:abc)),
            (_dg(-0.0), _dg(0.0)), (_dg(2^56 - 1), _dg(2^56)),
            (_dg(big(2)^70), _dg(2.0^70)),
            (_dg(Rational{BigInt}(1 // 3)), _dg(1 / 3)), (_dg(true), _dg(1)),
            (_dg([1.0]), _dg(1.0)), (_dg(""), _ds(""))
        ]
        for (x, y) in pairs
            @test !_dident(x, y)                                  # the pair IS two literals
            # at the top, inside a compound, and inside a list
            for (h, at) in (
                (_de(:p, x, y), d -> (child(d, 2), child(d, 3))),
                (
                    _de(:p, _de(:f, x, y)),
                    d -> (child(child(d, 2), 2), child(child(d, 2), 3))
                ),
                (_de(:p, _dcons(x, _dcons(y, mk_nil(_D)))),
                    d -> (child(child(d, 2), 2), child(child(child(d, 2), 3), 2)))
            )
                dx, dy = at(_ddecompile(h))
                hx, hy = at(h)                                    # the terms the head holds
                ok = _dsame(dx, hx) && _dsame(dy, hy) && _dident(dx, x) && _dident(dy, y)
                ok ||
                    println(stderr, "  literals changed: ", ix_text(h), " decompiled with ",
                        ix_text(dx), "::", typeof(lk_value(dx)), " and ", ix_text(dy), "::",
                        typeof(lk_value(dy)))
                @test ok
            end
        end
        # the literal table holds the very terms, in code order
        h = _de(:p, _dg(1), _de(:g, _dg(1.0)))
        cl = _dclause(h)
        @test length(cl.literals) == 3                            # 1, g, 1.0
        @test cl.literals[1] === child(h, 2) && cl.literals[3] === child(child(h, 3), 2)
        @test lk_eq(cl.literals[2], _ds(:g))
    end

    @testset "a random head comes back as a variant of itself" begin
        rng = Xoshiro(20261004)
        nexpr = 0
        for k in 1:500
            shared = [_dv(10_000 * k + j) for j in 1:3]
            h = _de("dk$k", [_darg(rng, shared, 1) for _ in 1:rand(rng, 1:5)]...)
            d = _ddecompile(h)
            ok = LK.is_variant_ptr(d, h)
            ok || println(
                stderr,
                "  not a variant: ",
                ix_text(h),
                "\n    decompiled: ",
                ix_text(d)
            )
            @test ok
            nexpr += count(
                i -> kind(child(h, i)) === EXPR && kind(child(child(h, i), 1)) !== SYM,
                2:nchildren(h))
        end
        @test nexpr > 0                                           # `$expr/n` arguments were drawn
    end

    @testset "the code reads its table: each literal once, argKey == indexOfWord" begin
        rng = Xoshiro(4)
        for k in 1:300
            shared = [_dv(20_000 * k + j) for j in 1:3]
            h = _de("dt$k", [_darg(rng, shared, 1) for _ in 1:rand(rng, 1:5)]...)
            cl = _dclause(h)
            @test sort(_dliteral_refs(cl)) == 1:length(cl.literals)   # no orphan, none twice
            for i in 0:(nchildren(h) - 2)
                @test LK.argKey(LK.Code(cl, 1), i) == LK.indexOfWord(child(h, i + 2))
            end
        end
    end

    @testset "a grounded value SWI has no type for: an opaque literal (DIVERGES)" begin
        t, v = _dg(true), _dg([1.0, 2.0])
        @test number_kind(t) === NUM_OTHER && number_kind(v) === NUM_OTHER
        cl = _dclause(_de(:p, t, v))
        @test [cl.codes[1], cl.codes[3]] == [LK.H_ATOM, LK.H_ATOM]
        @test lk_value(cl.literals[1]) === true                   # the value itself
        @test lk_value(cl.literals[2]) == [1.0, 2.0]
        @test LK.argKey(LK.Code(cl, 1), 0) == LK.indexOfWord(t)
        @test LK.argKey(LK.Code(cl, 1), 1) == LK.indexOfWord(v)
        # matched by `gnd_equal`: `true` is not `1`, `[1.0]` not `1.0` — indexed or not
        pr = ix_pred(_D, :o, 1)
        for x in (_dg(true), _dg(false), _dg([1.0]), _dg(1), _dg(1.0))
            ix_assertz!(pr, _de(:o, x))
        end
        for i in 1:30
            ix_assertz!(pr, _de(:o, _ds("k$i")))                  # enough clauses to index
        end
        for x in (_dg(true), _dg(false), _dg([1.0]), _dg(1), _dg(1.0))
            got = first.(ix_call(pr, _de(:o, x)))
            @test lk_eq(got, _D[_de(:o, x)])
            @test lk_eq(got, first.(ix_call_unindexed(pr, _de(:o, x))))
            @test _dsame(child(only(got), 2), x)
        end
    end
end
