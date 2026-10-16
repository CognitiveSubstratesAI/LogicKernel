# ORIGINAL: the clause index's argument view (V4a); upstream exercises it only through its VM.
# test/db/test_index_argv.jl — upstream's index readers (`indexOfWord`, `canIndex`, `is_var`)
# FOLLOW REFERENCES, so a BOUND argument keys by its value and narrows the search. The kernel's
# key reader `_argv_key` dereferences through the bindings for both views of the arguments —
# `argv_frame`, a frame's argument slots (what the VM passes, where a slot almost always holds a
# variable bound to the argument; read on the WORDS since L1c sub-commit 5), and `argv_term`, a goal's
# arguments (`argv_at`). Without the dereference no bound argument would narrow, and the determinism
# the VM reports would differ from swipl's. TERM-GENERIC.
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
    pvm = LK.PutVarMap()  # one PutVarMap: these puts share their variables as one record does (L1b boundary, user 2026-10-14)
    LK.putSlotValue!(ld, base + 1, a1, pvm)
    LK.putSlotValue!(ld, base + 2, a2, pvm)
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
        # both views key the argument by its value, 7, and see no variable there
        @test LK._argv_key(argv, 0) == LK.indexOfWord(ld, _ag(7)) &&
            !LK._argv_is_var(argv, 0)
        c, more = _a_first(p, argv)
        @test c !== nothing && c.key == LK.indexOfWord(ld, _ag(7))  # the clause p(7, a) …
        @test !more                                             # … and no clause choice left
    end
    @test only(ix_call(p, mk_expr(_A, _A[_as(:p), X, Y]))) |> last  # det, through ix_call too
    # a chain of bindings is followed to its end: Z = X = 7
    Z = mk_var(_A, UInt64(3))
    LK.Trail!(ld, var_key(Z), X)
    for argv in _a_views(ld, Z, Y)
        c, more = _a_first(p, argv)
        @test c !== nothing && c.key == LK.indexOfWord(ld, _ag(7)) && !more
    end
    # unbound: every clause is a candidate, and a clause choice remains
    W = mk_var(_A, UInt64(4))
    for argv in _a_views(ld, W, Y)
        c, more = _a_first(p, argv)
        @test c !== nothing && more
    end
end

# ── a VALUE's hashed key is never a reserved word (the divergence audit, S05; user, 2026-10-06;
# narrowed in L1d step 4) ─────────────────────────────────────────────────────────────────────────
# `listSupervisor` takes `ATOM_nil` and `FUNCTOR_dot2` as identity. Since L1d step 4 an atom's and a
# functor's key is its WORD — a handle that cannot collide: `[]` IS `ATOM_nil` and `'[|]'/2` IS
# `FUNCTOR_dot2`, the built-in words of every database — but a value's key is a HASH
# (`_value_index_key`), so one equal to either reserved word is moved off it (`_unreserved`). The
# colliding hash is FED IN through a test-only grounded value whose `gnd_key` is the reserved number.
struct _IxCollidingGnd end
LogicKernel.kind(::_IxCollidingGnd) = GND
LogicKernel.gnd_key(::_IxCollidingGnd) = UInt64(LK.ATOM_nil)

@testset "a value's hashed key is never a reserved word (S05); an atom's key is its word (L1d-4)" begin
    g = LK._gnd_index_key(UInt64(LK.ATOM_nil))                      # a grounded key that hashed so
    @test g != LK.ATOM_nil && g != 0 && !LK.isFunctor(g)
    @test LK._value_index_key(_IxCollidingGnd()) == g               # end to end: both key sides' function
    for w in (LK.MK_ATOM(UInt64(12345)), LK.MK_FUNCTOR(UInt64(999), UInt64(3)), LK.word(17))
        @test LK._unreserved(w) == w                                # every other key is unchanged
    end
    # the reserved words ARE the database's built-in words, the same in every database
    gd = LK.PL_global_data{_A}()
    ld = LK.PL_local_data{_A}(gd)
    @test gd.atom_nil_w == LK.ATOM_nil && gd.functor_dot2 == LK.FUNCTOR_dot2
    gd2 = LK.PL_global_data{_A}()
    @test gd2.atom_nil_w == gd.atom_nil_w && gd2.functor_dot2 == gd.functor_dot2
    @test LK.indexOfWord(ld, mk_nil(_A)) == LK.ATOM_nil
    @test LK.indexOfWord(
        ld, mk_expr(_A, _A[mk_sym(_A, Symbol("[|]")), mk_gnd(_A, 1), mk_nil(_A)])
    ) == LK.FUNCTOR_dot2
    # `[]` (a reserved symbol) and the text atom `'[]'` are two atoms, two words (swipl 10.1.16:
    # `[](a) \== '[]'(a)`): their keys, and their functors' keys, differ by construction
    @test LK.indexOfWord(ld, mk_sym(_A, Symbol("[]"))) != LK.ATOM_nil
    @test LK.indexOfWord(ld, mk_expr(_A, _A[mk_nil(_A), _as(:a)])) !=
        LK.indexOfWord(ld, mk_expr(_A, _A[mk_sym(_A, Symbol("[]")), _as(:a)]))
end
