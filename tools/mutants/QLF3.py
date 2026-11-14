# ORIGINAL: QLF3's mutant list — the counterpart is pl-qlf.c (qlfGetInt64, qlfGetInt32 as qlfGetUInt32, qlfGetDouble, qlfGetStringW,
# getAtom, getBlobType, loadXRc, lookupXrId, loadInclude, qlfLoadIncludes, qlfLoadFileHash, qlfModuleInfo, qlfInfo) and pl-fli.c
# (PL_put_dict) at the pin 18168e62.
# tools/mutants/QLF3.py — the mutation battery of QLF3 row 11 (`'$qlf_module'/2`, the XR reader), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate_ci.py one). Format: tools/mutate_drive.py's: `id`, `file`, `old` (must occur
# EXACTLY once), `new`, optional `equivalent` and `targets`. Every mutant is killed by a named testset (a fixture of `_QM_FIX`) of
# test/files/test_qlf_module_swipl.jl or by the table of test/files/test_qlf_swipl.jl:
#   * REC = the testset "'$qlf_module'/2 answers the module record" (the pinned swipl dict of every fixture: basic, nosrc,
#     super_ref, many, bigref, inc72, inc68, nilcons, ucs, blobfun, latin, nonmodule, redef_class, two_s, cdup_same, srcline,
#     ints, real);
#   * ERR = the testset "'$qlf_module'/2 errors by name" (the e_* fixtures: the messages and the index of each);
#   * MOV = the testset "'$qlf_module'/2 of a QLF file that has moved" (pushPathTranslation, qlfFixSourcePath);
#   * the `$qlf_module` entries of the table of test_qlf_swipl.jl share the same code (every call of `qlfInfo`).
# NOT LISTED (each with its reason, `equivalent` here: no row can fail them):
#   * qlfGetDouble's byte order and its `c & 0xff` mask (pl-qlf.jl:1131): the eight bytes of the time of a source file (and of an
#     XR_FLOAT) are read and dropped, no answer shows the value; only their count (QLF3-30) and the EOF check (QLF3-31) are visible;
#   * `shift += 7` of qlfGetUInt32 (pl-qlf.jl:1115) and `v |= c << shift` of its middle bytes (pl-qlf.jl:1114): reached only by an
#     id of 16384 or more (a third byte); the greatest id of the fixtures is 141 (`bigref`), the table of test_qlf_swipl.jl none;
#   * the mask of the first byte of the multi-byte branch of qlfGetUInt32, `v = c & 0x7f` (pl-qlf.jl:1103): that branch is taken
#     only when bit 7 of `c` is clear, so the mask changes nothing (the mask of the one-byte branch, `return c & 0x7f`, IS a
#     mutant: QLF3-3);
#   * the restore of the stream's encoding in qlfGetStringW's `finally` (pl-qlf.jl:1178): after the string no `Sgetcode` follows
#     (the next reads are `Qgetc`, which ignores the encoding), so the stream's encoding is not observed;
#   * `isvalid(Char, ...)` of qlfGetStringW (pl-qlf.jl:1173): it differs from the UTF-8 decoder's own answer only for a surrogate
#     or a code point above 0x10ffff, which no fixture holds (upstream keeps those in its `wchar_t` buffer);
#   * the `Sclose(s)` and `popPathTranslation` skipped by an ErrorException out of qlfInfo (the stream leaks, as C ends the process
#     there): each error row uses a fresh `PL_global_data`, no assertion reads the leaked state.
# TARGETS (audit D-0238): the code is reached by `'$qlf_module'/2` (this file) and, for qlfInfo, qlfLoadFileHash, qlfGetInt64,
# qlfGetString, loadFileName and the path translation, by `'$qlf_sources'/2` and the other rows of the table of
# test_qlf_swipl.jl and test_qlf_stale_swipl.jl (the index of a real qcompile'd file, the hash and version rows); so the three files are the list.
TARGETS = ["test/files/test_qlf_module_swipl.jl", "test/files/test_qlf_swipl.jl", "test/files/test_qlf_stale_swipl.jl"]
T = TARGETS
Q = "src/pl-qlf.jl"
F = "src/pl-fli.jl"
MUTANTS = [
    # ---- qlfGetUInt32 (the id of an XR_REF) and qlfGetInt64
    dict(id="QLF3-1 qlfGetUInt32 starts the second byte at shift 8: a two-byte id 132 reads as 260 (KILL REC: the bigref row, an id never stored)",
         file=Q, targets=T,
         old="""        v = c & 0x7f
        shift = 7""",
         new="""        v = c & 0x7f
        shift = 8"""),
    dict(id="QLF3-2 the last byte of qlfGetUInt32 is shifted one bit too far (KILL REC: the bigref row, the XR_REF 132)",
         file=Q, targets=T,
         old="""                v |= l << shift
                return v""",
         new="""                v |= l << (shift + 1)
                return v"""),
    dict(id="QLF3-3 qlfGetUInt32 keeps the 0x80 flag of a one-byte id: 0x81 reads as 129, never stored (KILL REC: the super_ref row, the XR_REF 1)",
         file=Q, targets=T,
         old="return c & 0x7f",
         new="return c"),
    dict(id="QLF3-4 qlfGetInt64 reads the third byte of an integer one bit too far (KILL REC: the ints row, the arity 70000)",
         file=Q, targets=T,
         old="""                v |= b << shift
                shift += 7""",
         new="""                v |= b << shift
                shift += 8"""),
    # ---- the XR id table (loadXRc, lookupXrId)
    dict(id="QLF3-5 an XR_FUNCTOR takes two ids: the refs after it meet another entry (KILL REC: the many row, the XR_REF to the third functor; bigref)",
         file=Q, targets=T,
         old="""    elseif c == XR_FUNCTOR
        id = (t.id += 1)""",
         new="""    elseif c == XR_FUNCTOR
        id = (t.id += 2)"""),
    dict(id="QLF3-6 an XR_FUNCTOR takes its id after its name, not before (C: `id = ++state->XR->id` first): the refs meet the names (KILL REC: the many row; bigref)",
         file=Q, targets=T,
         old="""    elseif c == XR_FUNCTOR
        id = (t.id += 1)
        nx = loadXR(ld, state)""",
         new="""    elseif c == XR_FUNCTOR
        nx = loadXR(ld, state)
        id = (t.id += 1)"""),
    dict(id="QLF3-7 an XR_ATOM takes two ids: the first atom is not at id 1 (KILL REC: the super_ref row, its XR_REF 1 is never stored; many)",
         file=Q, targets=T,
         old="""    elseif c == XR_ATOM
        id = (t.id += 1)""",
         new="""    elseif c == XR_ATOM
        id = (t.id += 2)"""),
    dict(id="QLF3-8 lookupXrId refuses id 1 (`id < 2`) (KILL REC: the super_ref row, the XR_REF 1; the many and bigref rows)",
         file=Q, targets=T,
         old="if id < 1 || id > length(t.entries)",
         new="if id < 2 || id > length(t.entries)"),
    dict(id="QLF3-9 lookupXrId lets id 0 through (`id < 0`): a BoundsError, not the format error (KILL ERR: the e_zeroref row)",
         file=Q, targets=T,
         old="if id < 1 || id > length(t.entries)",
         new="if id < 0 || id > length(t.entries)"),
    # ---- qlfModuleInfo
    dict(id="QLF3-10 a source adds no key to the dict: `dlen += 1` becomes `+= 0` (KILL REC: the basic row, the file pair)",
         file=Q, targets=T,
         old="dlen += 1",
         new="dlen += 0"),
    dict(id="QLF3-11 four keys with no source: `dlen = 3` becomes 4, the `file` key holds a fresh variable (KILL REC: the nosrc row)",
         file=Q, targets=T,
         old="dlen = 3",
         new="dlen = 4"),
    dict(id="QLF3-12 the `S` (super) property is no property: a format error (KILL REC: the super_ref and two_s rows)",
         file=Q, targets=T,
         old="elseif p == Int('S')",
         new="elseif p == Int('s')"),
    dict(id="QLF3-13 the no-source byte is `+` for `-` (KILL REC: the nosrc row)",
         file=Q, targets=T,
         old="if c == Int('-')",
         new="if c == Int('+')"),
    dict(id="QLF3-14 the class is read and not unified: the `class` value stays unbound (KILL REC: the basic row; the redef_class row, where the second C must fail)",
         file=Q, targets=T,
         old="PL_unify_atom(ld, av + 1, _xr_atom(state, cx)) || return false",
         new="(_xr_atom(state, cx); true) || return false"),
    dict(id="QLF3-15 the export list is not closed: its tail stays a variable (KILL REC: the basic row, the many row, the b_right bound row)",
         file=Q, targets=T,
         old="PL_unify_nil(ld, extail) || return false",
         new="true || return false"),
    dict(id="QLF3-16 `_qlf_mkeys` gives the keys `class` and `module` swapped (KILL REC: the basic row, every pair)",
         file=Q, targets=T,
         old="for k in (:module, :class, :exports, :file)",
         new="for k in (:class, :module, :exports, :file)"),
    dict(id="QLF3-17 a record that starts with F is an answer, not a failure (KILL REC: the nonmodule row)",
         file=Q, targets=T,
         old="""    elseif c0 == Int('F')
        return false""",
         new="""    elseif c0 == Int('F')
        return true"""),
    dict(id="QLF3-18 an XR_NIL is the atom `[|]` (KILL REC: the nilcons row, `[]/2`)",
         file=Q, targets=T,
         old="""    elseif c == XR_NIL
        return xr_atom{T}(mk_nil(T))""",
         new="""    elseif c == XR_NIL
        return xr_atom{T}(mk_sym(T, Symbol("[|]")))"""),
    dict(id="QLF3-19 an XR_CONS is the atom `[]` (KILL REC: the nilcons row, `'[|]'/2`)",
         file=Q, targets=T,
         old="""return xr_atom{T}(mk_sym(T, Symbol("[|]")))             # ATOM_dot""",
         new="""return xr_atom{T}(mk_nil(T))             # ATOM_dot"""),
    # ---- the text of an atom (getAtom, qlfGetStringW, getBlob)
    dict(id="QLF3-20 the bytes of an atom are read as UTF-8, not ISO Latin-1 (KILL REC: the latin row, the byte 0xE9)",
         file=Q, targets=T,
         old="text = String(Char[Char(b) for b in buf])",
         new="text = String(copy(buf))"),
    dict(id="QLF3-21 a blob of type `ucs_text` is read as a plain text atom (KILL REC: the ucs row, the wide characters)",
         file=Q, targets=T,
         old="if tx.name === :ucs_text",
         new="if tx.name === :text"),
    dict(id="QLF3-22 every blob type is accepted: the unknown type `weird` is read as text (KILL ERR: the e_blobtype row, the named refusal)",
         file=Q, targets=T,
         old="""if !(name in ("text", "ucs_text", "reserved_symbol"))""",
         new="""if false"""),
    # ---- the versions of the include entries and the hash
    dict(id="QLF3-23 the version-70 include layout starts at 73: a version 72 include is read as the old one (KILL REC: the inc72 row)",
         file=Q, targets=T,
         old="""    if state.saved_version >= 70
        loadFileName(ld, state)""",
         new="""    if state.saved_version >= 73
        loadFileName(ld, state)"""),
    dict(id="QLF3-24 the version-70 include layout starts at 68: a version 68 include is read as the new one (KILL REC: the inc68 row)",
         file=Q, targets=T,
         old="""    if state.saved_version >= 70
        loadFileName(ld, state)""",
         new="""    if state.saved_version >= 68
        loadFileName(ld, state)"""),
    dict(id="QLF3-25 the hash after a file name starts at version 73: version 72 files are read with no hash (KILL REC: the basic row and every v72 row; the sources rows of test_qlf_swipl.jl)",
         file=Q, targets=T,
         old="if state.saved_version >= 72",
         new="if state.saved_version >= 73"),
    dict(id="QLF3-26 an `I` entry (version 68) is no include: a format error (KILL REC: the inc68 row)",
         file=Q, targets=T,
         old="elseif c == Int('I') || c == Int('L')",
         new="elseif c == Int('L')"),
    # ---- qlfInfo
    dict(id="QLF3-27 the module information is read only when Q_MODULE is NOT set (KILL REC: every row; the `$qlf_module` entries of test_qlf_swipl.jl)",
         file=Q, targets=T,
         old="if rval && (flags & Q_MODULE) != 0",
         new="if rval && (flags & Q_MODULE) == 0"),
    dict(id="QLF3-28 the path translation is pushed for Q_FILES only: a moved file's source is told as saved (KILL MOV: the translated row)",
         file=Q, targets=T,
         old="if (flags & (Q_MODULE | Q_FILES)) != 0",
         new="if (flags & Q_FILES) != 0"),
    # ---- PL_put_dict
    dict(id="QLF3-29 PL_put_dict leaves the tag a variable (KILL REC: every row, the tag `#`)",
         file=F, targets=T,
         old="tag != 0 && (ld.gstack[p + 1] = tag)",
         new="false && (ld.gstack[p + 1] = tag)"),
    dict(id="QLF3-30 qlfGetDouble reads seven bytes: every row with a source is misaligned (KILL REC: the basic row; the srcline and real rows)",
         file=Q, targets=T,
         old="""    for i in 0:7
        c = Qgetc(s)
        c == EOF && error("Unexpected end-of-file in QLT file")""",
         new="""    for i in 0:6
        c = Qgetc(s)
        c == EOF && error("Unexpected end-of-file in QLT file")"""),
    dict(id="QLF3-31 an EOF inside the time of a source is not seen by qlfGetDouble: the later error has another text (KILL ERR: the e_eofdouble row)",
         file=Q, targets=T,
         old="""c == EOF && error("Unexpected end-of-file in QLT file")""",
         new="""c == EOF - 1 && error("Unexpected end-of-file in QLT file")"""),
    dict(id="QLF3-32 an EOF inside an atom is not seen by getAtom (KILL ERR: the e_eofatom row)",
         file=Q, targets=T,
         old="""c == EOF && error("Unexpected EOF on intermediate code file at offset""",
         new="""c == EOF - 1 && error("Unexpected EOF on intermediate code file at offset"""),
    dict(id="QLF3-33 an EOF inside a wide string is the invalid code point -1, not the end of the file (KILL ERR: the e_eofwide row's message)",
         file=Q, targets=T,
         old="""c < 0 && error("Unexpected EOF in UCS atom")""",
         new="""c < -1 && error("Unexpected EOF in UCS atom")"""),
    dict(id="QLF3-34 an arity of -1 is a functor (`arity < -1`) (KILL ERR: the e_negarity row)",
         file=Q, targets=T,
         old="arity < 0 && qlfLoadError(state)",
         new="arity < -1 && qlfLoadError(state)"),
    dict(id="QLF3-35 an XR entry that is no atom is taken as one (KILL ERR: the e_modint row, the module name an XR_INT)",
         file=Q, targets=T,
         old="x isa xr_atom || qlfLoadError(state)",
         new="true || qlfLoadError(state)"),
    dict(id="QLF3-36 an export entry that is no functor is read as one (KILL ERR: the e_funint row)",
         file=Q, targets=T,
         old="fx isa xr_functor || qlfLoadError(state)",
         new="true || qlfLoadError(state)"),
]
