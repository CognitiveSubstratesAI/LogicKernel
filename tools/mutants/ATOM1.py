# ORIGINAL: ATOM1's mutant list (atoms holding the character 0, term interface escape) — no swipl-devel counterpart.
# tools/mutants/ATOM1.py — the mutation battery of ATOM1 (an atom whose text holds the character 0 is named by the
# ESCAPED text: src/term_interface.jl `atom_escape` / `atom_unescape`; `sym_text` / `sym_first_byte` of the default term
# answer for the text (src/default_term.jl); `compareAtoms` and `_cmp_escaped` order by the text (src/pl-prims.jl);
# `_atom_from_text` escapes (src/pl-read.jl)). Run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh
# run). Format: tools/mutate_drive.py's (as F31.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional
# `equivalent` and `targets`. Killed by the conformance rows of test/core_lang/term_interface_testlib.jl (the testset
# "an atom holding the character 0": text, first byte, identity, order, with swipl 10.1.20's order rows; run on both
# term types by test/core_lang/test_term_interface.jl), by test/core_lang/test_atom_words.jl (the round trip of the atom
# of a text with a 0) and by the swipl row files that build such an atom (t25/t26/t31 of test_setlocale_swipl.jl, t12 of
# test_locale_swipl.jl, t42/t43 of test_char_type_swipl.jl, q17 of test_p2b_swipl.jl, the `'a\0\b'` read of
# test_read_swipl.jl, zero_codes of test_bips.jl). Verdicts: written by the battery, not yet run. Every `old` was checked
# to occur exactly once in its file at wip/atom1 (a text count by python, no Julia: the code is UNTESTED, blind); the
# `old` strings are in the repo's formatted style BEFORE `tools/warm.sh fmt`: RE-FIT any that fmt rewraps.
# NOT LISTED (each with its reason):
#   * `_unescaped_byte`'s `b2 == 0x81 && return (0xc0, i + 2)` (a raw 0xC0 byte of the text): EQUIVALENT on the order. Without
#     it a raw 0xC0 reads as the two bytes 0xC0 0x81, so the text's comparison sequence is the text's with a 0x81 inserted
#     after each raw 0xC0; two texts agree on a prefix exactly when their sequences do, they differ first at the same unit
#     (the first byte of either sequence at that unit is the unit itself, 0xC0 against anything else), and a shorter text is
#     shorter in both: the order is the same. (`atom_unescape`'s own 0x81 branch is mutant M6, observable.)
#   * `sym_first_byte`'s guard `b == 0xc0 || return b`: dropped, the second byte is read for every atom, and the result
#     differs only for a name whose SECOND byte is 0x80 (U+0100 `Ā`, C4 80 and the like); for the empty name it reads one byte
#     past the terminator: an out-of-bounds read of the runtime's memory, not a verdict (the playbook's runaway rule).
#   * `_cmp_escaped`'s call from `compareAtoms` when only ONE name holds 0xC0 versus both: the condition `ca == 0xc0 || cb == 0xc0`
#     is M1's whole line; its two halves are not mutated apart (each half alone leaves a row where the other name is the
#     escaped one, and the order rows put the escape on both sides of every pair: `compareStandard(nul(x), nul(y))` and the
#     swapped call).
#   * AllocCheck (test/static_analysis.jl) on `compareAtoms`, `_cmp_escaped`, `_unescaped_byte`, `sym_first_byte`: a mutant
#     that allocates there is the static analysis's, not a row's; not a mutant here.
# TARGETS (audit D-0238): each mutant lists every test file that exercises its mutated code, the step's own files first
# (a run stops at the first target that decides). compareAtoms is reached through compareStandard: `git grep -l -E
# "compareStandard|compareAtoms" -- test` names 31 files, the compare-heavy ones are in TCMP; sym_text and sym_first_byte
# are read in nearly every test file (`git grep -l -E "sym_text|sym_first_byte" -- test`), the files that read an atom
# made by the reader or the text builtins from a text WITH a 0 are in TROWS: a mutant of these helpers is killed at its
# first rows or survives them all (a survivor is then reported with the full list in the verdict table, to be read by name).
TI = [
    "test/core_lang/test_term_interface.jl",
    "test/core_lang/test_default_term.jl",
    "test/core_lang/test_atom_words.jl",
]
TROWS = [
    "test/core_lang/test_atom_table.jl",
    "test/core_lang/test_bips.jl",
    "test/core_lang/test_setlocale_swipl.jl",
    "test/core_text/test_locale_swipl.jl",
    "test/core_text/test_char_type_swipl.jl",
    "test/core_lang/test_p2b_swipl.jl",
    "test/core_lang/test_read_swipl.jl",
    "test/core_text/test_roundtrip_swipl.jl",
    "test/core_text/test_write_family_swipl.jl",
    "test/core_text/test_write_swipl.jl",
    "test/core_text/test_canonical_readatom_swipl.jl",
    "test/core_lang/test_format_swipl.jl",
]
TCMP = TI + [
    "test/core_lang/test_sort.jl",
    "test/core_lang/test_compare_swipl.jl",
    "test/core_lang/test_compare_cells.jl",
    "test/core_lang/test_blob.jl",
] + TROWS
TARGETS = TI + TROWS + [
    "test/core_lang/test_sort.jl",
    "test/core_lang/test_compare_swipl.jl",
    "test/core_lang/test_compare_cells.jl",
    "test/core_lang/test_blob.jl",
]            # the union of the mutants' targets: the baseline must be green on every one
D = "src/default_term.jl"
I = "src/term_interface.jl"
P = "src/pl-prims.jl"
R = "src/pl-read.jl"
MUTANTS = [
    # ── compareAtoms / _cmp_escaped (src/pl-prims.jl): the standard order is the text's ──
    dict(id="ATOM1-M1 compareAtoms ignores the escape: names are compared as raw bytes, 0xC0 0x80 sorts after ASCII (KILL the order rows of the testlib on both term types: [97,0] < [97,97], [0] < [97], [97,0,98] < [97,1]; zero_codes of test_bips.jl is the upstream row)",
         file=P, targets=TCMP,
         old="            (ca == 0xc0 || cb == 0xc0) && return _cmp_escaped(pa, pb)   # an escape: by the characters\n",
         new=""),
    dict(id="ATOM1-M2 sym_first_byte: the name 0xC0 0x80 answers 0xC0, not the first byte of the text, 0x00 (KILL the first-byte rows of the testlib: sym_first_byte(nul([0x00])) == 0x00)",
         file=D, targets=TI + TROWS,
         old="    return b2 == 0x80 ? 0x00 : b\n",
         new="    return b\n"),
    dict(id="ATOM1-M3 atom_unescape is the identity: sym_text of an atom holding the character 0 answers the escaped name (KILL the text rows of the testlib, test_atom_words.jl's round trip, t25/t26/t31, t42/t43)",
         file=I, targets=TI + TROWS,
         old="    findfirst(==(0xc0), cu) === nothing && return str\n",
         new="    return str\n"),
    dict(id="ATOM1-M4 _atom_from_text does not escape: Symbol(text) of a text with a 0 throws Julia's ArgumentError (KILL test_atom_words.jl, t25/t26/t31, t12, t42/t43, q17, the read of 'a\\0\\b')",
         file=R, targets=TI + TROWS,
         old="    return mk_sym(T, Symbol(atom_escape(str)))\n",
         new="    return mk_sym(T, Symbol(str))\n"),
    dict(id="ATOM1-M5 _cmp_escaped: the text that ends first is the greater one (KILL the testlib rows [97,0] < [97,0,98] and [0] < [0,120] with both names escaped, both term types)",
         file=P, targets=TCMP,
         old="        enda && return CMP_LESS                         # the shorter text first\n",
         new="        enda && return CMP_GREATER                      # the shorter text first\n"),
    # ── beyond the five of the design: the unescape of a raw 0xC0, the escape of a raw 0xC0, the text of the default term ──
    dict(id="ATOM1-M6 atom_unescape: the pair 0xC0 0x81 stays two bytes (KILL the testlib's `atom_unescape(atom_escape(raw)) == raw` and the raw-0xC0 rows: sym_text(r_c0))",
         file=I, targets=TI,
         old="        elseif b == 0xc0 && i < n && cu[i + 1] == 0x81\n",
         new="        elseif false && b == 0xc0 && i < n && cu[i + 1] == 0x81\n"),
    dict(id="ATOM1-M7 atom_escape: a raw 0xC0 byte is not escaped (KILL the testlib's `atom_escape(raw) == ...` row)",
         file=I, targets=TI,
         old="        elseif b == 0xc0\n            push!(out, 0xc0, 0x81)\n",
         new="        elseif false\n            push!(out, 0xc0, 0x81)\n"),
    dict(id="ATOM1-M8 the default term's sym_text answers the name, not the text (KILL the text rows of the testlib and test_default_term.jl)",
         file=D, targets=TI + TROWS,
         old="    return atom_unescape(String(t.name))              # the name holds no 0: ATOM1's escape\n",
         new="    return String(t.name)\n"),
]
