# ORIGINAL: L1b stage C3 — an atom bound to a cell is its own word (pl-data.h `TAG_ATOM`), in the engine's atom table; upstream has no counterpart test (its cells always hold words).
# test/core_lang/test_atom_words.jl — white-box, on every term type:
#   * a cell bound to a symbol holds an ATOM word (`isAtomW`), with no value-table entry, and reads
#     back as the same symbol; the same symbol bound twice is one word;
#   * `[]` (a reserved symbol) and `'[]'` (a text atom) are two words, each read back as itself;
#   * a symbol above Latin-1 is a wide (`ucs_atom`) atom, read back unchanged;
#   * other values still go to the value table (small integers too, until the instructions read
#     words: building a term from `consInt` would allocate on every read);
#   * an atom holding the character 0 cannot be a `Symbol`: planted by hand (no binding can make
#     one yet — every atom in the engine comes from a symbol), its read raises
#     `AtomNotRepresentableError` with the atom's code points (the L1 plan §2c; user, 2026-10-14);
#   * `Undo!` unbinds an atom-bound cell like any other;
#   * the atom table is the DATABASE's (`GD->atoms`, before C6b: user, 2026-10-15): two engines on
#     one database share their atom words — an atom one of them made is the same word in the other
#     — an engine on another database has its own table, and a query refuses an engine made for
#     another database.
using Test, LogicKernel
const LK = LogicKernel

# TERM TYPES PER CHUNK: REFERENCE — built on the term layer; every type in CI and at milestones
include(joinpath(@__DIR__, "..", "term_under_test.jl"))
const _AW = lk_term_type(Union{Int64, Float64, String})
_aw_sym(n) = lk_sym(_AW, Symbol(n))
_aw_var(k::UInt64) = mk_var(_AW, k)
"The word in the cell variable `k` names."
_aw_word(ld, k::UInt64) = ld.gstack[LK._cell_pos(ld, k)]

@testset "an atom bound to a cell is its own word, read back as the same symbol" begin
    ld = LK.PL_local_data{_AW}(LK.PL_global_data{_AW}())
    x, y = LK.allocGlobalVars!(ld, 1), LK.allocGlobalVars!(ld, 1)
    n0 = length(ld.vtable)
    LK.Trail!(ld, x, _aw_sym(:foo))
    w = _aw_word(ld, x)
    @test LK.isAtomW(w) && length(ld.vtable) == n0              # no value-table entry
    @test lk_eq(LK.deRef(ld, _aw_var(x)), _aw_sym(:foo))
    LK.Trail!(ld, y, _aw_sym(:foo))
    @test _aw_word(ld, y) == w                                  # one atom per symbol
    @test LK.atomValue(ld.atoms, w).name[1:3] == Vector{UInt8}(codeunits("foo"))
end

@testset "`[]` and `'[]'` are two words, each read back as itself" begin
    ld = LK.PL_local_data{_AW}(LK.PL_global_data{_AW}())
    a, b = LK.allocGlobalVars!(ld, 1), LK.allocGlobalVars!(ld, 1)
    LK.Trail!(ld, a, LK.mk_nil(_AW))
    LK.Trail!(ld, b, _aw_sym("[]"))
    @test LK.isAtomW(_aw_word(ld, a)) && LK.isAtomW(_aw_word(ld, b))
    @test _aw_word(ld, a) != _aw_word(ld, b)
    @test _aw_word(ld, a) == LK.builtin_atom("nil")             # ATOM_nil, the reserved symbol
    @test LK.is_nil(LK.deRef(ld, _aw_var(a)))
    rb = LK.deRef(ld, _aw_var(b))
    @test !LK.is_reserved_symbol(rb) && LK.sym_text(rb) == "[]"
end

@testset "a symbol above Latin-1 is a wide atom, read back unchanged" begin
    ld = LK.PL_local_data{_AW}(LK.PL_global_data{_AW}())
    x, y = LK.allocGlobalVars!(ld, 1), LK.allocGlobalVars!(ld, 1)
    LK.Trail!(ld, x, _aw_sym("āé"))
    @test LK.atomValue(ld.atoms, _aw_word(ld, x)).type === LK.ucs_atom
    @test lk_eq(LK.deRef(ld, _aw_var(x)), _aw_sym("āé"))
    LK.Trail!(ld, y, _aw_sym("é"))                              # Latin-1: a text atom
    @test LK.atomValue(ld.atoms, _aw_word(ld, y)).type === LK.text_atom
    @test lk_eq(LK.deRef(ld, _aw_var(y)), _aw_sym("é"))
end

@testset "other values go to the value table; a small integer is its own word (L1d step 4)" begin
    ld = LK.PL_local_data{_AW}(LK.PL_global_data{_AW}())
    x, y = LK.allocGlobalVars!(ld, 1), LK.allocGlobalVars!(ld, 1)
    n0 = length(ld.vtable)
    LK.Trail!(ld, x, lk_gnd(_AW, 7.5))                          # a float: an indirect, the value table
    w = _aw_word(ld, x)
    @test LK.tagex(w) == (LK.TAG_COMPOUND | LK.STG_RESERVED) && length(ld.vtable) == n0 + 1
    @test lk_eq(LK.deRef(ld, _aw_var(x)), lk_gnd(_AW, 7.5))
    LK.Trail!(ld, y, lk_gnd(_AW, Int64(7)))                     # a small integer: its tagged word
    wy = _aw_word(ld, y)
    @test wy == LK.consInt(7) && length(ld.vtable) == n0 + 1    # no value-table entry
    @test lk_eq(LK.deRef(ld, _aw_var(y)), lk_gnd(_AW, Int64(7)))
end

@testset "an atom holding the character 0 raises AtomNotRepresentableError on its read" begin
    ld = LK.PL_local_data{_AW}(LK.PL_global_data{_AW}())
    x = LK.allocGlobalVars!(ld, 1)
    a0b = LK.lookupAtom(ld.atoms, UInt8[0x61, 0x00, 0x62])      # 'a\0b', planted by hand
    ld.gstack[LK._cell_pos(ld, x)] = a0b
    err = try
        LK.deRef(ld, _aw_var(x))
        nothing
    catch e
        e
    end
    @test err isa LK.AtomNotRepresentableError && err.codes == UInt32[0x61, 0x00, 0x62]
    ld.gstack[LK._cell_pos(ld, x)] = UInt64(0)
end

@testset "Undo! unbinds an atom-bound cell" begin
    ld = LK.PL_local_data{_AW}(LK.PL_global_data{_AW}())
    x = LK.allocGlobalVars!(ld, 1)
    m = LK.Mark(ld)
    LK.Trail!(ld, x, _aw_sym(:bar))                             # older than the mark: trailed
    @test LK.isAtomW(_aw_word(ld, x))
    LK.Undo!(ld, m)
    @test kind(LK.deRef(ld, _aw_var(x))) === VAR && _aw_word(ld, x) == 0
end

@testset "two engines on one database share their atom words (GD->atoms)" begin
    gd = LK.PL_global_data{_AW}()
    l1, l2 = LK.PL_local_data{_AW}(gd), LK.PL_local_data{_AW}(gd)
    @test l1.atoms === gd.atoms && l2.atoms === gd.atoms
    x1, x2 = LK.allocGlobalVars!(l1, 1), LK.allocGlobalVars!(l2, 1)
    LK.Trail!(l2, x2, _aw_sym("made_by_l2"))                    # a new atom, made through l2
    LK.Trail!(l1, x1, _aw_sym("made_by_l2"))
    @test _aw_word(l1, x1) == _aw_word(l2, x2)
    @test lk_eq(LK.deRef(l1, _aw_var(x1)), _aw_sym("made_by_l2"))   # through l1's own cache
    other = LK.PL_local_data{_AW}(LK.PL_global_data{_AW}())
    @test other.atoms !== gd.atoms
    @test_throws AssertionError LK.PL_open_query(
        LK.PL_global_data{_AW}(), l1, nothing, LK.PL_Q_NORMAL,
        LK.lookupProcedure(_aw_sym(:p), 0, LK.MODULE_user(gd)), 0
    )
end
