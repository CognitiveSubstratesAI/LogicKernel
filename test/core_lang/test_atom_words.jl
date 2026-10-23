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
"The word in the cell at global position `p`."
_aw_word(ld, p::Int) = ld.gstack[p]
"Bind the cell at `p` to the value `v`'s word (the cell arm of `Trail!` until f3-3)."
_aw_bind!(ld, p::Int, v) = LK._bind_const!(ld, p, LK._word_of!(ld, v))
"The value the bound cell at `p` holds: an atom's symbol, or a value's term (as `_cell_value` read them until f3-3)."
function _aw_read(ld, p::Int)
    w = ld.gstack[p]
    return LK.isAtomW(w) ? LK._atom_value(ld, w) : LK._value_term(ld, w)
end

@testset "an atom bound to a cell is its own word, read back as the same symbol" begin
    ld = LK.PL_local_data{_AW}(LK.PL_global_data{_AW}())
    x, y = LK.allocGlobalCells!(ld, 1), LK.allocGlobalCells!(ld, 1)
    n0 = length(ld.vtable)
    _aw_bind!(ld, x, _aw_sym(:foo))
    w = _aw_word(ld, x)
    @test LK.isAtomW(w) && length(ld.vtable) == n0              # no value-table entry
    @test lk_eq(_aw_read(ld, x), _aw_sym(:foo))
    _aw_bind!(ld, y, _aw_sym(:foo))
    @test _aw_word(ld, y) == w                                  # one atom per symbol
    @test LK.atomValue(ld.atoms, w).name[1:3] == Vector{UInt8}(codeunits("foo"))
end

@testset "`[]` and `'[]'` are two words, each read back as itself" begin
    ld = LK.PL_local_data{_AW}(LK.PL_global_data{_AW}())
    a, b = LK.allocGlobalCells!(ld, 1), LK.allocGlobalCells!(ld, 1)
    _aw_bind!(ld, a, LK.mk_nil(_AW))
    _aw_bind!(ld, b, _aw_sym("[]"))
    @test LK.isAtomW(_aw_word(ld, a)) && LK.isAtomW(_aw_word(ld, b))
    @test _aw_word(ld, a) != _aw_word(ld, b)
    @test _aw_word(ld, a) == LK.builtin_atom("nil")             # ATOM_nil, the reserved symbol
    @test LK.is_nil(_aw_read(ld, a))
    rb = _aw_read(ld, b)
    @test !LK.is_reserved_symbol(rb) && LK.sym_text(rb) == "[]"
end

@testset "a symbol above Latin-1 is a wide atom, read back unchanged" begin
    ld = LK.PL_local_data{_AW}(LK.PL_global_data{_AW}())
    x, y = LK.allocGlobalCells!(ld, 1), LK.allocGlobalCells!(ld, 1)
    _aw_bind!(ld, x, _aw_sym("āé"))
    @test LK.atomValue(ld.atoms, _aw_word(ld, x)).type === LK.ucs_atom
    @test lk_eq(_aw_read(ld, x), _aw_sym("āé"))
    _aw_bind!(ld, y, _aw_sym("é"))                              # Latin-1: a text atom
    @test LK.atomValue(ld.atoms, _aw_word(ld, y)).type === LK.text_atom
    @test lk_eq(_aw_read(ld, y), _aw_sym("é"))
end

@testset "other values go to the value table; a small integer is its own word (L1d step 4)" begin
    ld = LK.PL_local_data{_AW}(LK.PL_global_data{_AW}())
    x, y = LK.allocGlobalCells!(ld, 1), LK.allocGlobalCells!(ld, 1)
    n0 = length(ld.vtable)
    _aw_bind!(ld, x, lk_gnd(_AW, 7.5))                          # a float: an indirect, the value table
    w = _aw_word(ld, x)
    @test LK.tagex(w) == (LK.TAG_COMPOUND | LK.STG_RESERVED) && length(ld.vtable) == n0 + 1
    @test lk_eq(_aw_read(ld, x), lk_gnd(_AW, 7.5))
    _aw_bind!(ld, y, lk_gnd(_AW, Int64(7)))                     # a small integer: its tagged word
    wy = _aw_word(ld, y)
    @test wy == LK.consInt(7) && length(ld.vtable) == n0 + 1    # no value-table entry
    @test lk_eq(_aw_read(ld, y), lk_gnd(_AW, Int64(7)))
end

@testset "an atom holding the character 0 raises AtomNotRepresentableError on its read" begin
    ld = LK.PL_local_data{_AW}(LK.PL_global_data{_AW}())
    x = LK.allocGlobalCells!(ld, 1)
    a0b = LK.lookupAtom(ld.atoms, UInt8[0x61, 0x00, 0x62])      # 'a\0b', planted by hand
    ld.gstack[x] = a0b
    err = try
        _aw_read(ld, x)
        nothing
    catch e
        e
    end
    @test err isa LK.AtomNotRepresentableError && err.codes == UInt32[0x61, 0x00, 0x62]
    ld.gstack[x] = UInt64(0)
end

@testset "Undo! unbinds an atom-bound cell" begin
    ld = LK.PL_local_data{_AW}(LK.PL_global_data{_AW}())
    x = LK.allocGlobalCells!(ld, 1)
    m = LK.Mark(ld)
    _aw_bind!(ld, x, _aw_sym(:bar))                             # older than the mark: trailed
    @test LK.isAtomW(_aw_word(ld, x))
    LK.Undo!(ld, m)
    @test _aw_word(ld, x) == 0                                  # setVar(*p)
end

@testset "two engines on one database share their atom words (GD->atoms)" begin
    gd = LK.PL_global_data{_AW}()
    l1, l2 = LK.PL_local_data{_AW}(gd), LK.PL_local_data{_AW}(gd)
    @test l1.atoms === gd.atoms && l2.atoms === gd.atoms
    x1, x2 = LK.allocGlobalCells!(l1, 1), LK.allocGlobalCells!(l2, 1)
    _aw_bind!(l2, x2, _aw_sym("made_by_l2"))                    # a new atom, made through l2
    _aw_bind!(l1, x1, _aw_sym("made_by_l2"))
    @test _aw_word(l1, x1) == _aw_word(l2, x2)
    @test lk_eq(_aw_read(l1, x1), _aw_sym("made_by_l2"))   # through l1's own cache
    other = LK.PL_local_data{_AW}(LK.PL_global_data{_AW}())
    @test other.atoms !== gd.atoms
    @test_throws AssertionError LK.PL_open_query(
        LK.PL_global_data{_AW}(), l1, nothing, LK.PL_Q_NORMAL,
        LK.lookupProcedure(_aw_sym(:p), 0, LK.MODULE_user(gd)), 0
    )
end
