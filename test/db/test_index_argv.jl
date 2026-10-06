# ORIGINAL: the clause index's argument view (V4a); upstream exercises it only through its VM.
# test/db/test_index_argv.jl — upstream's index readers (`indexOfWord`, `canIndex`, `is_var`)
# FOLLOW REFERENCES, so a BOUND argument keys by its value and narrows the search. The kernel's
# `argv_at` dereferences through the bindings for both views of the arguments — `argv_frame`, a
# frame's argument slots (what the VM passes, where a slot almost always holds a variable bound to
# the argument), and `argv_term`, a goal's arguments. Without the dereference no bound argument
# would narrow, and the determinism the VM reports would differ from swipl's. TERM-GENERIC.
using Test, LogicKernel
# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
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

# ── a hashed key is never a reserved word (the divergence audit, S05; user, 2026-10-06) ──────────
# `listSupervisor` takes `ATOM_nil` and `FUNCTOR_dot2` as identity, so a hashed key equal to either
# is moved off it (`_unreserved`, src/pl-index.jl). The colliding hashes are FED IN: to the key
# constructors, and through `indexOfWord` by a test-only symbol and grounded value whose interface
# hashes are exactly the reserved words' numbers.
struct _IxCollidingSym end
struct _IxCollidingGnd end
LogicKernel.kind(::_IxCollidingSym) = SYM
LogicKernel.is_nil(::_IxCollidingSym) = false
LogicKernel.sym_hash(::_IxCollidingSym) = UInt64(0x0052_4553_5652_4544)   # ATOM_nil's number
LogicKernel.kind(::_IxCollidingGnd) = GND
LogicKernel.gnd_key(::_IxCollidingGnd) = UInt64(LK.ATOM_nil)

@testset "a hashed key is never a reserved word (the divergence audit, S05)" begin
    n_nil = UInt64(0x0052_4553_5652_4544)
    @test LK.MK_ATOM(n_nil) == LK.ATOM_nil                         # the colliding hash
    a = LK._atom_key(n_nil)
    @test a != LK.ATOM_nil && a != LK.FUNCTOR_dot2 && !LK.isFunctor(a)
    @test a & 0x7f == LK.ATOM_nil & 0x7f                            # the tag is kept
    @test LK.indexOfWord(_IxCollidingSym()) == a                    # end to end
    n_dot = UInt64(0x0004_c495_354e_4f43)
    @test LK.MK_FUNCTOR(n_dot, UInt64(2)) == LK.FUNCTOR_dot2         # the colliding hash
    f = LK._functor_key(n_dot, 2)
    @test f != LK.FUNCTOR_dot2 && LK.isFunctor(f)
    @test (f >> LK.LMASK_BITS) & LK.F_ARITY_MASK == 2               # the arity is kept
    g = LK._gnd_index_key(UInt64(LK.ATOM_nil))                      # a grounded key that hashed so
    @test g != LK.ATOM_nil && g != 0 && !LK.isFunctor(g)
    @test LK.indexOfWord(_IxCollidingGnd()) == g                    # end to end
    for w in (LK.MK_ATOM(UInt64(12345)), LK.MK_FUNCTOR(UInt64(999), UInt64(3)), LK.word(17))
        @test LK._unreserved(w) == w                                # every other key is unchanged
    end
    # a functor's own hash cannot be steered to collide (Julia's `hash` mixes its seed, probed), so
    # that path is checked by STRUCTURE: the functor word goes through the guarded constructor
    ci = code_lowered(LK._functor_word, (UInt64, Int))[1]
    @test any(x -> x isa GlobalRef && x.name === :_functor_key, ci.code)   # the callee, lowered
    # the real `[]` and list cell keep the reserved words
    @test LK.indexOfWord(mk_nil(_A)) == LK.ATOM_nil
    @test LK.indexOfWord(
        mk_expr(_A, _A[mk_sym(_A, Symbol("[|]")), mk_gnd(_A, 1), mk_nil(_A)])
    ) ==
        LK.FUNCTOR_dot2
end
