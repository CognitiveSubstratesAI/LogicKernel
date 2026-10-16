# ORIGINAL: L1b stage C6b — the constant instructions on WORDS (H_ATOM, B_ATOM, H_NIL, B_NIL, L_ATOM, L_NIL; pl-vmi.c) and the atoms' symbols held by the DATABASE; upstream has no counterpart test (its atom record is its name, its operands are words).
# test/core_lang/test_constant_words.jl — white-box and swipl-differential, on every term type:
#   * the symbol store (`atom_symbols`) has the atom array's layout: block `idx` holds the `2^idx`
#     atoms from index `2^idx`, allocated whole and never moved;
#   * an atom made through engine A's compiler is read back by engine B on the same database with no
#     lookup miss — B never converted it, and B's own conversion finds the same word (user,
#     2026-10-15: no per-engine cache);
#   * the `H_ATOM`/`B_ATOM` operand is packed: the literal (exactly) and the atom word; an opaque
#     literal (NUM_OTHER) has no word;
#   * `h_const` on the words (`_h_const_word!`): a slot holding the constant's word matches, another
#     atom word fails, a cell reached through references matches, binds when unbound (trailed under
#     a mark, undone by `Undo!`) and fails on another atom; a value-table word or a `SLOT_VALUE`
#     slot is left to the terms;
#   * answers: heads and bodies with atoms, `[]` and `'[]'`, small integers and compounds, through
#     bindings, chains of cells and backtracking — the kernel's answers equal swipl's.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
include(joinpath(@__DIR__, "rules_common.jl"))

_kw_s(n) = lk_sym(_R, Symbol(n))

@testset "the symbol store: the atom array's blocks, allocated whole, never moved" begin
    s = LK.atom_symbols{_R}()
    idxs = (1, 2, 3, 4, 7, 8, 63, 64, 1000)
    for i in idxs
        LK.setAtomSymbol!(s, i, _kw_s("s$i"))
    end
    for i in idxs
        @test sym_key(LK.atomSymbol(s, i)) == sym_key(_kw_s("s$i"))
    end
    @test LK.atomSymbol(s, 5) === nothing                       # its block exists, the entry not
    @test LK.atomSymbol(s, 5000) === nothing                    # no block at all
    b = s.blocks[LK.MSB(1000) + 1]
    @test length(b) == 1 << LK.MSB(1000)                        # 512 entries: 512..1023
    LK.setAtomSymbol!(s, 1001, _kw_s("s1001"))
    @test s.blocks[LK.MSB(1000) + 1] === b                      # the same block: never moved
    # the atom array's own layout for the same index
    gd = LK.PL_global_data{_R}()
    i = gd.atoms.highest - 1
    @test length(something(gd.atoms.array[LK.MSB(i) + 1])) == 1 << LK.MSB(i)
end

# L1c-6 (user, 2026-10-16: an alternative-type allocation that grew with n): the VM's `[]` word is
# the database's, made once, and the index keys it as `[]` from the store — no term read
@testset "ATOM_nil's word is the database's, keyed as [] without a term" begin
    gd = LK.PL_global_data{_R}()
    ld = LK.PL_local_data{_R}(gd)
    @test ld.atom_nil_w == gd.atom_nil_w == LK._atom_word!(ld, gd.atom_nil)
    @test gd.atom_nil_w == LK.ATOM_nil                          # the built-in word IS the key (L1d-4)
    @test LK._index_key_loc(ld, LK.DU_WORD, gd.atom_nil_w, 0) ==
        LK.indexOfWord(ld, gd.atom_nil)
end

@testset "an atom made through engine A's compiler reads back in engine B: no miss" begin
    gd = LK.PL_global_data{_R}()
    lda = LK.PL_local_data{_R}(gd)
    ldb = LK.PL_local_data{_R}(gd)
    @test lda.atom_symbols === gd.atom_symbols && ldb.atom_symbols === gd.atom_symbols
    user = LK.MODULE_user(gd)
    z = _kw_s("kw_c6b_fresh_atom")
    pr = LK.lookupProcedure(_kw_s("kw_p"), 1, user)
    cl = LK.compileClause(gd, lda, _rf("kw_p", z), nothing, pr, user)
    j = findfirst(==(LK.H_ATOM), cl.codes)
    @test j !== nothing
    op = cl.codes[j + 1]
    w = LK.atom_operand_word(op)
    @test w != 0 && LK.isAtomW(w)
    @test cl.literals[LK.atom_literal(op)] === z                # the literal, exactly
    @test !haskey(ldb.atom_words, sym_key(z))                   # B never converted it
    @test sym_key(LK._atom_value(ldb, w)) == sym_key(z)         # …and reads it: no miss
    # B asked for the TEXT A created — a symbol built anew, so B's cache misses — falls through to
    # the database's table and gets A's word: no second atom (user, 2026-10-15: a cache, not a table)
    n = gd.atoms.highest
    z2 = _kw_s("kw_c6b_fresh_atom")
    @test LK._atom_word!(ldb, z2) == w
    @test gd.atoms.highest == n                                 # nothing created
    @test ldb.atom_words[sym_key(z2)] == w                      # now cached in B
    @test LK._atom_word!(ldb, z) == w                           # B's own conversion: the same atom
    # B runs A's clause: the head's word matches B's argument
    LK.assertDefinition!(gd, pr.definition, cl, LK.CL_END)
    @test _rcall(_RDB(gd, ldb, user), _rf("kw_p", _rv(1))) ==
        [("kw_p(kw_c6b_fresh_atom)", true)]
    @test _rcall(_RDB(gd, ldb, user), _rf("kw_p", z)) == [("kw_p(kw_c6b_fresh_atom)", true)]
end

@testset "an opaque literal (NUM_OTHER) packs no atom word" begin
    O = lk_term_type(Union{Int64, Bool})
    gd = LK.PL_global_data{O}()
    user = LK.MODULE_user(gd)
    v = lk_gnd(O, true)
    pr = LK.lookupProcedure(lk_sym(O, :kw_o), 1, user)
    cl = LK.compileClause(
        gd, LK.PL_local_data{O}(gd), mk_expr(O, O[lk_sym(O, :kw_o), v]), nothing, pr, user
    )
    j = findfirst(==(LK.H_ATOM), cl.codes)
    @test j !== nothing && LK.atom_operand_word(cl.codes[j + 1]) == 0
    @test cl.literals[LK.atom_literal(cl.codes[j + 1])] === v
end

"An engine and three term references' slots on it, and the words of atoms `a` and `b`."
function _kw_engine()
    ld = LK.PL_local_data{_R}(LK.PL_global_data{_R}())
    r = LK.PL_new_term_refs(ld, 3)
    return ld,
    r + 1, r + 2, r + 3, LK._atom_word!(ld, _kw_s(:a)),
    LK._atom_word!(ld, _kw_s(:b))
end

@testset "h_const on the words: a slot's own atom word" begin
    ld, s, _, _, wa, wb = _kw_engine()
    ld.slots[s] = wa
    @test LK._h_const_word!(ld, s, wa) == LK.H_CONST_MATCH
    @test LK._h_const_word!(ld, s, wb) == LK.H_CONST_FAIL
    LK.setSlotValue!(ld, s, _rf("f", _kw_s(:a)))                # a compound: its word (L1c)
    @test LK._is_gcompound(ld.slots[s])
    @test LK._h_const_word!(ld, s, wa) == LK.H_CONST_FAIL
    LK.setSlotValue!(ld, s, _rg(Int64(1)))                      # a small integer: SLOT_VALUE
    @test LK._h_const_word!(ld, s, wa) == LK.H_CONST_TERMS
end

@testset "h_const on the words: a cell, bound, trailed under a mark, undone" begin
    ld, s, t, _, wa, wb = _kw_engine()
    p = LK._slot_new_var!(ld, s)
    m = LK.Mark(ld)                                             # the cell is older than the mark
    n0 = length(ld.trail)
    @test LK._h_const_word!(ld, s, wa) == LK.H_CONST_MATCH      # bindConst(k, c)
    @test ld.gstack[p] == wa && length(ld.trail) == n0 + 1
    @test sym_key(LK.deRef(ld, LK.slotValue(ld, s))) == sym_key(_kw_s(:a))
    @test LK._h_const_word!(ld, s, wa) == LK.H_CONST_MATCH      # *k == c, nothing trailed
    @test length(ld.trail) == n0 + 1
    @test LK._h_const_word!(ld, s, wb) == LK.H_CONST_FAIL
    LK.Undo!(ld, m)
    @test ld.gstack[p] == 0                                     # setVar(*p)
    # a cell newer than the mark is bound without a trail entry (upstream: `p >= mark_bar`)
    q = LK._slot_new_var!(ld, t)
    n1 = length(ld.trail)
    @test LK._h_const_word!(ld, t, wb) == LK.H_CONST_MATCH
    @test ld.gstack[q] == wb && length(ld.trail) == n1
    LK.DiscardMark(ld, m)
end

@testset "h_const on the words: through a chain of cells; a value-table word is left to the terms" begin
    ld, s, t, _, wa, wb = _kw_engine()
    p1 = LK._slot_new_var!(ld, s)
    p2 = LK._slot_new_var!(ld, t)
    ld.gstack[p1] = LK.makeRefG(p2)                             # a reference cell (`_slot_link!` follows one)
    @test LK._h_const_word!(ld, s, wa) == LK.H_CONST_MATCH
    @test ld.gstack[p2] == wa && ld.gstack[p1] == LK.makeRefG(p2)
    @test LK._h_const_word!(ld, s, wb) == LK.H_CONST_FAIL
    # bound through the value table (a float: an indirect, as upstream's): undecided on the words; a
    # small INTEGER is a tagged word since L1d step 4 — decided on the words, against an atom word or
    # against its own tagged word (`*k == c`)
    ld2, u, v, _, wa2, _ = _kw_engine()
    k = LK._cell_key(ld2, LK._slot_new_var!(ld2, u))
    LK.Trail!(ld2, k, _rg(7.0))
    @test LK._h_const_word!(ld2, u, wa2) == LK.H_CONST_TERMS
    ld3, u3, _, _, wa3, _ = _kw_engine()
    k3 = LK._cell_key(ld3, LK._slot_new_var!(ld3, u3))
    LK.Trail!(ld3, k3, _rg(Int64(7)))
    @test LK._h_const_word!(ld3, u3, wa3) == LK.H_CONST_FAIL
    @test LK._h_const_word!(ld3, u3, LK.consInt(7)) == LK.H_CONST_MATCH
    # a cell bound to a cell variable holds a REFERENCE (L1c: upstream's `makeRefG`): followed, the
    # unbound cell at its end bound
    k2 = LK._cell_key(ld2, LK._slot_new_var!(ld2, v))
    pw = LK._slot_new_var!(ld2, u)
    LK.Trail!(ld2, k2, mk_var(_R, LK._cell_key(ld2, pw)))
    @test LK.isRef(ld2.gstack[LK._cell_pos(ld2, k2)])
    @test LK._h_const_word!(ld2, v, wa2) == LK.H_CONST_MATCH
    @test ld2.gstack[pw] == wa2
end

@testset "the constant instructions answer as swipl" begin
    X, Y, Z, R = (_rv(k) for k in 1:4)
    a, b, nil, tnil = _kw_s(:a), _kw_s(:b), LK.mk_nil(_R), _kw_s("[]")
    id(p, q) = _rf("kw_id", p, q)
    pair(p, q) = _rf("-", p, q)
    eq(p, q) = _rf("=", p, q)
    conj(gs...) = foldr((g, r) -> _rf(",", g, r), gs)
    clauses = Tuple{_R, Union{Nothing, _R}}[
        (_rf("kw_h", a), nothing), (_rf("kw_h", nil), nothing),
        (_rf("kw_h", tnil), nothing),
        (_rf("kw_h", _rg(Int64(1))), nothing), (_rf("kw_h", _rf("f", a)), nothing),
        (id(X, X), nothing),
        (_rf("kw_two", a, a), nothing), (_rf("kw_two", X, b), nothing),
        (_rf("kw_k", nil), nothing), (_rf("kw_k", tnil), nothing),
        # a head constant against a cell bound through another (a chain, the value table until L1d)
        (_rf("kw_chain", R), conj(id(X, Y), _rf("kw_h", Y), eq(R, pair(X, Y)))),
        # a binding made by a head constant is undone on backtracking
        (_rf("kw_undo", R),
            _rf(";", conj(_rf("kw_h", X), _rf("==", X, b)), eq(R, X))),
        # an older cell bound across a choice point, then tested by another head
        (_rf("kw_ch", R), conj(_rf("kw_h", X), _rf("kw_k", X), eq(R, X))),
        # body constants: B_ATOM/B_NIL into argument slots, and L_ATOM/L_NIL in a last call
        (_rf("kw_b", R), conj(id(a, R), _kw_s("true"))),
        (_rf("kw_bn", R), conj(id(nil, R), _kw_s("true"))),
        (_rf("kw_l", R), id(a, R)),
        (_rf("kw_ln", R), _rf("kw_two", Z, R)),
        (_rf("kw_lc", R), conj(_rf("kw_h", Z), _rf("kw_two", nil, R))),
        (_rf("kw_lt", R), _rf("kw_k", tnil))
    ]
    goals = _R[
        _rf("kw_h", X), _rf("kw_h", a), _rf("kw_h", b), _rf("kw_h", nil), _rf("kw_h", tnil),
        _rf("kw_h", _rg(Int64(1))), _rf("kw_h", _rf("f", Y)), _rf("kw_h", _rf("f", b)),
        _rf("kw_two", Y, Y), _rf("kw_two", a, Y), _rf("kw_two", b, b),
        _rf("kw_chain", R), _rf("kw_undo", R), _rf("kw_ch", R), _rf("kw_b", R),
        _rf("kw_bn", R), _rf("kw_l", R), _rf("kw_ln", R), _rf("kw_lc", R), _rf("kw_lt", R)
    ]
    ours = _rlines(_rdb(clauses), goals)
    @test count(==("end"), ours) == length(goals)
    if _R_SWIPL
        @test ours == _rswipl(clauses, goals)
    else
        @test_skip "swipl is not on PATH: the answers are not compared"
    end
end
