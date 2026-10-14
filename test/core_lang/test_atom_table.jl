# ORIGINAL: the atom table (L1b stage A, src/pl-atom.jl) against pl-atom.c's rules and src/ATOMS at the pin; upstream has no unit test of its atom table (its tests reach it through atom built-ins, which read the table only from stage C here).
# test/core_lang/test_atom_table.jl — white-box, each case hand-written with its reason:
#   * THE DATA: src/pl-atom.jl's generated region is exactly what tools/gen_atoms.jl makes of
#     src/ATOMS AT THE PIN (`git show <commit>:src/ATOMS`) wherever a checkout is found; without
#     one, the test asserts there is none, so it cannot skip silently;
#   * the built-ins: 1048 atoms (`defatom` writes `ATOM("")` first, then the 1047 `A` lines),
#     index 1 the empty atom, `.` registered as `[|]`, every built-in found again by lookup;
#   * lookup: one atom per (bytes, length, type) — the character 0 is part of the text, so `a\0b`,
#     `a`, `""` and `"\0"` are four atoms (a C-string comparison would merge them);
#   * canonicalisation (`textToAtom`): Latin-1 text is a `text_atom`, wider text a `ucs_atom`; the
#     same text as UTF-8 and as wide characters is one atom;
#   * rehash: 20,000 new atoms (more than `ATOMHASHSIZE * 2`), each found again, every index
#     distinct, the built-ins unmoved;
#   * the reserved symbols: `[]` is a `reserved_symbol`, so the text atom `'[]'` is another atom;
#     the blob types' ranks (text 1, then wide text, reserved 0).
# NOT HERE, with stage C (when terms are read through the table): the swipl differentials of the
# L1 plan's A list (`[] == '[]'`, the standard order by text, the character 0 in atom built-ins) and
# the BLOB atoms of grounded host values.
using Test, LogicKernel
const LK = LogicKernel

const _AT_CHECKOUT = get(
    ENV, "LOGICKERNEL_UPSTREAM_SWIPL_DEVEL", joinpath(homedir(), "dev-zone", "swipl-devel")
)

"A fresh atom table, as a database's (`do_init_atoms!`)."
_at_table() = LK.do_init_atoms!(LK.atoms_t())

"The bytes of `s` (its UTF-8 code units)."
_at_bytes(s::AbstractString) = Vector{UInt8}(codeunits(s))

"The atom a word names in `atoms`."
_at_atom(atoms, w::UInt64) = LK.atomValue(atoms, w)

if isdir(joinpath(_AT_CHECKOUT, ".git"))
    @testset "src/pl-atom.jl's built-in atoms are src/ATOMS at the pin (tools/gen_atoms.jl)" begin
        m = Module(:GenAtomsCheck)
        Base.include(m, joinpath(pkgdir(LogicKernel), "tools", "gen_atoms.jl"))
        commit = Base.invokelatest(m.pinned_commit, pkgdir(LogicKernel))
        ids, texts = Base.invokelatest(m.atoms_at_pin, _AT_CHECKOUT, commit)
        dst = joinpath(pkgdir(LogicKernel), "src", "pl-atom.jl")
        reg = Base.invokelatest(m.region, ids, texts, commit)
        @test Base.invokelatest(m.rewrite, dst, reg) == read(dst, String)
        @test Tuple(texts) == LK._BUILTIN_ATOMS && Tuple(ids) == LK._BUILTIN_ATOM_IDS
        # defatom.c numbers both from 1: `int atom=1; int functor=1;` — the empty atom is index 1;
        # the 333 functors (stage B) each name an atom of the table
        src = read(`git -C $_AT_CHECKOUT show $commit:src/ATOMS`, String)
        fs = Base.invokelatest(m.parse_functors, src)
        @test length(fs) == 333 && all(f -> f[1] in ids, fs)
        @test count(l -> startswith(l, 'A'), split(src, '\n')) == 1047 == length(texts) - 1
        # the generator refuses an escape it does not handle, and reads `\\` as one backslash
        @test_throws ErrorException Base.invokelatest(m.c_unescape, "a\\nb", "fixture")
        @test Base.invokelatest(m.c_unescape, "\\\\=", "fixture") == "\\="
    end
else
    @info "ATOM TABLE DATA CHECK NOT RUN: no swipl-devel checkout at $_AT_CHECKOUT."
    @testset "the atom data check is skipped only where there is no checkout" begin
        @test !isdir(joinpath(_AT_CHECKOUT, ".git"))
    end
end

@testset "the built-in atoms: 1048, index 1 the empty atom, `.` as `[|]`" begin
    atoms = _at_table()
    @test length(LK._BUILTIN_ATOMS) == 1048 == length(LK._BUILTIN_ATOM_IDS)
    @test LK._BUILTIN_ATOMS[1] == "" && LK._BUILTIN_ATOM_IDS[1] == ""
    @test LK._BUILTIN_ATOMS[2] == "UTF-8" && LK._BUILTIN_ATOM_IDS[2] == "UTF_8"
    @test atoms.highest == 1049 && atoms.builtin == 1049 && atoms.no_hole_before == 1049
    @test atoms.statistics_atoms == 1048        # no atom made at start-up beyond the built-ins
    dot = LK.builtin_atom("dot")
    @test _at_atom(atoms, dot).name == _at_bytes("[|]")          # SWI-7: not "."
    @test LK.lookupAtom(atoms, _at_bytes("[|]")) == dot
    # every built-in text atom is found again by lookup, at its own index
    for (i, s) in enumerate(LK._BUILTIN_ATOMS)
        a = LK.fetchAtomArray(atoms, i)
        a.type === LK.text_atom || continue
        @test LK.lookupAtom(atoms, a.name, a.length) ==
            (UInt64(i) << LK.LMASK_BITS) | LK.TAG_ATOM
    end
    @test LK.indexAtom(LK.builtin_atom("text")) ==
        findfirst(==("text"), LK._BUILTIN_ATOM_IDS)
    @test_throws ArgumentError LK.builtin_atom("no_such_atom_id")
end

@testset "lookup: one atom per (bytes, length, type); the character 0 is text" begin
    atoms = _at_table()
    a1 = LK.lookupAtom(atoms, _at_bytes("hello"))
    @test LK.lookupAtom(atoms, _at_bytes("hello")) == a1                    # the same atom
    a0b = LK.lookupAtom(atoms, UInt8[0x61, 0x00, 0x62])                     # "a\0b", 3 bytes
    a = LK.lookupAtom(atoms, _at_bytes("a"))
    @test a0b != a && _at_atom(atoms, a0b).length == 3                      # not a C string
    @test LK.lookupAtom(atoms, UInt8[0x61, 0x00, 0x62]) == a0b
    nul = LK.lookupAtom(atoms, UInt8[0x00])
    empty = LK.lookupAtom(atoms, UInt8[])
    @test nul != empty && _at_atom(atoms, nul).length == 1 &&
        _at_atom(atoms, empty).length == 0
    @test empty == (UInt64(1) << LK.LMASK_BITS) | LK.TAG_ATOM                # `ATOM_`: index 1
    # a prefix of the bytes passed (`length`) is the key, as upstream's (s, length)
    @test LK.lookupAtom(atoms, _at_bytes("hello world"), 5) == a1
    # a new atom (a name src/ATOMS does not have): the next index, its name padded with one 0
    # byte (`text_atom`'s padding)
    h = atoms.highest
    n = LK.lookupAtom(atoms, _at_bytes("lk_not_a_builtin_atom"))
    @test LK.indexAtom(n) == h && atoms.highest == h + 1
    @test _at_atom(atoms, n).name == UInt8[_at_bytes("lk_not_a_builtin_atom"); 0x00]
    @test _at_atom(atoms, n).references ==
        UInt32(1) | LK.ATOM_VALID_REFERENCE | LK.ATOM_RESERVED_REFERENCE
end

@testset "canonicalisation: Latin-1 is a text atom, wider text a wide one, one atom per text" begin
    atoms = _at_table()
    utf8(s) = LK.PL_chars_t(_at_bytes(s), length(s), LK.ENC_UTF8, false)
    wide(s) = LK.PL_chars_t(
        Vector{UInt8}(reinterpret(UInt8, UInt32[UInt32(c) for c in s])), length(s),
        LK.ENC_WCHAR,
        false
    )
    e = LK.textToAtom(atoms, utf8("é"))                         # U+00E9: Latin-1
    @test _at_atom(atoms, e).type === LK.text_atom && _at_atom(atoms, e).name[1:1] == [0xe9]
    ā = LK.textToAtom(atoms, utf8("ā"))                         # U+0101: wide
    @test _at_atom(atoms, ā).type === LK.ucs_atom && _at_atom(atoms, ā).length == 4
    @test LK.textToAtom(atoms, wide("ā")) == ā                  # the same text: one atom
    @test LK.textToAtom(atoms, wide("é")) == e                  # demoted to Latin-1
    @test LK.textToAtom(atoms, utf8("abc")) == LK.lookupAtom(atoms, _at_bytes("abc"))
    a0ā = LK.textToAtom(atoms, utf8("a\0ā"))
    @test _at_atom(atoms, a0ā).type === LK.ucs_atom && _at_atom(atoms, a0ā).length == 12
    @test LK.textToAtom(atoms, wide("a\0ā")) == a0ā
    # ONE ATOM PER TEXT, whatever the encoding it arrives in (the user's review, 2026-10-14: UTF-8
    # is never canonical, so a text above ASCII cannot hash as two encodings): the same atom WORD
    # from UTF-8, ISO Latin-1 and wide characters — for a Latin-1 character, for one above 0xFF
    # (no Latin-1 form), and for texts holding the character 0
    latin1(bs::Vector{UInt8}) =
        LK.PL_chars_t(copy(bs), length(bs), LK.ENC_ISO_LATIN_1, false)
    @test LK.textToAtom(atoms, utf8("é")) == LK.textToAtom(atoms, latin1(UInt8[0xe9])) ==
        LK.textToAtom(atoms, wide("é")) == e
    @test LK.textToAtom(atoms, utf8("ā")) == LK.textToAtom(atoms, wide("ā")) == ā
    a0e = LK.textToAtom(atoms, latin1(UInt8[0x61, 0x00, 0xe9]))
    @test LK.textToAtom(atoms, utf8("a\0é")) == LK.textToAtom(atoms, wide("a\0é")) == a0e
    @test _at_atom(atoms, a0e).type === LK.text_atom && _at_atom(atoms, a0e).length == 3
    @test LK.textToAtom(atoms, utf8("a\0ā")) == LK.textToAtom(atoms, wide("a\0ā"))
    # a UTF-8 text is never canonical: canonicalising it gives ISO Latin-1 or wide text
    for s in ("abc", "é", "ā", "a\0é")
        t = utf8(s)
        @test LK.PL_canonicalise_text(t) == 1 && t.canonical
        @test t.encoding in (LK.ENC_ISO_LATIN_1, LK.ENC_WCHAR)
    end
    # wide text must be Unicode: a surrogate is refused (0, ERR_TEXT_INVALID_CODE_POINT)
    bad = LK.PL_chars_t(
        Vector{UInt8}(reinterpret(UInt8, UInt32[0xd800])), 1, LK.ENC_WCHAR, false
    )
    @test LK.PL_canonicalise_text(bad) == LK.ERR_TEXT_INVALID_CODE_POINT
    @test LK.textToAtom(
        atoms,
        LK.PL_chars_t(
            Vector{UInt8}(reinterpret(UInt8, UInt32[0xd800])), 1, LK.ENC_WCHAR, false
        )
    ) == 0
    # the blob types' ranks: text 1, wide text 2 once registered, reserved symbols 0
    ranks = Dict(r.type.name => r.rank for r in atoms.types)
    @test ranks["text"] == 1 && ranks["ucs_text"] == 2 && ranks["reserved_symbol"] == 0
    @test atoms.nontext_rank == 0
    pads = Dict(r.type.name => r.padding for r in atoms.types)
    @test pads["text"] == 1 && pads["ucs_text"] == 4 && pads["reserved_symbol"] == 1
end

@testset "rehash: 20,000 new atoms, each found again; the built-ins unmoved" begin
    atoms = _at_table()
    builtins = [LK.fetchAtomArray(atoms, i) for i in 1:length(LK._BUILTIN_ATOMS)]
    @test atoms.table.buckets == LK.ATOMHASHSIZE
    ws = [LK.lookupAtom(atoms, _at_bytes("atom_$i")) for i in 1:20_000]
    @test allunique(ws)
    @test atoms.table.buckets > LK.ATOMHASHSIZE                    # it rehashed
    @test atoms.table.buckets * 2 >= atoms.statistics_atoms
    @test all(i -> LK.lookupAtom(atoms, _at_bytes("atom_$i")) == ws[i], 1:20_000)
    @test all(i -> LK.fetchAtomArray(atoms, i) === builtins[i], eachindex(builtins))
    @test LK.lookupAtom(atoms, _at_bytes("text")) == LK.builtin_atom("text")
end

@testset "the reserved symbols: `[]` is not the text atom '[]'" begin
    atoms = _at_table()
    nil = LK.builtin_atom("nil")
    @test _at_atom(atoms, nil).type === LK.reserved_symbol
    @test _at_atom(atoms, nil).name == _at_bytes("[]")
    for id in ("dict", "trienode", "no_value", "term_t_free")
        @test _at_atom(atoms, LK.builtin_atom(id)).type === LK.reserved_symbol
    end
    quoted = LK.lookupAtom(atoms, _at_bytes("[]"))                 # the text atom '[]'
    @test quoted != nil && _at_atom(atoms, quoted).type === LK.text_atom
    @test first(LK.lookupBlob(atoms, _at_bytes("[]"), 2, LK.reserved_symbol)) == nil
end

@testset "a database holds its own atom table" begin
    gd1 = LK.PL_global_data{LK.DefaultTerm}()
    gd2 = LK.PL_global_data{LK.DefaultTerm}()
    @test gd1.atoms.initialised && gd1.atoms !== gd2.atoms
    w = LK.lookupAtom(gd1.atoms, _at_bytes("only_in_one"))
    @test LK.indexAtom(w) == gd2.atoms.highest                     # gd2 has not got it
    @test LK.lookupAtom(gd1.atoms, _at_bytes("only_in_one")) == w
end

@testset "PL_get_text: a wide code list is UTF-8 and NOT canonical; its atom is the wide text's" begin
    T = LK.DefaultTerm
    gd = LK.PL_global_data{T}()
    ld = LK.PL_local_data{T}()
    cons(h, t) = mk_expr(T, T[mk_sym(T, Symbol("[|]")), h, t])
    codes = foldr(cons, [mk_gnd(T, Int64(c)) for c in (0x61, 0x101)]; init=mk_nil(T))
    fid = LK.PL_open_foreign_frame(ld)
    l = LK.PL_new_term_ref(ld)
    LK.putSlotValue!(ld, l + 1, codes)
    text = LK.PL_get_text(ld, l, LK.CVT_LIST)
    @test text !== nothing && text.encoding === LK.ENC_UTF8 && !text.canonical
    w = LK.textToAtom(gd.atoms, text)
    @test text.canonical && text.encoding === LK.ENC_WCHAR
    wide = LK.PL_chars_t(
        Vector{UInt8}(reinterpret(UInt8, UInt32[0x61, 0x101])), 2, LK.ENC_WCHAR, false
    )
    @test w == LK.textToAtom(gd.atoms, wide) && _at_atom(gd.atoms, w).type === LK.ucs_atom
    LK.PL_close_foreign_frame(ld, fid)
end
