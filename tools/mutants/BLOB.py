# ORIGINAL: BLOB's mutant list — no swipl-devel counterpart.
# tools/mutants/BLOB.py — the mutation battery of BLOB (non-text atoms, blob/2, in the term interface: pl-atom.c blob types,
# pl-incl.h isTextAtom, pl-fli.c PL_is_blob / PL_is_callable / charCode, pl-prims.c compareAtoms (type rank), pl-write.c
# writeAtomToStream (blob branch), pl-termhash.c variant_sha1 (type name)), run ONCE, in CI (.github/workflows/mutation.yml;
# locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as AV6.py).
# Killed by test/core_lang/test_blob.jl (182 tests per term type).
# HAND-RUN 2026-10-28 (D-0104), reference type, each mutant applied alone and reverted: 14/14 CAUGHT, 0 EQUIVALENT.
# M2, M5, M7, M8, M9, M10, M11 are killed only by the rows of test_blob.jl's last testset ("writer, char_code, variant_sha1,
# compiled body"). M9 (pl-comp.jl _body_functor, blob goal) is reachable only by a DIRECT lookupBodyProcedure(gd, goal, tm) call:
# compileSubClause! turns a blob goal away first (pl-comp.jl isTextAtom branch, `else return NOT_CALLABLE`), so assertz((foo:-Blob))
# does not kill it; the row calls lookupBodyProcedure itself. M11 needs a compound whose functor NAME is a blob.
# Verdicts: evidence/BLOB/mutants_verdict.tsv (lk-channel).
# default_term.jl mutants run on the reference type only (the alt types have their own blob code in alt_term.jl).
TB = ["test/core_lang/test_blob.jl"]
TARGETS = TB                                         # the baseline's targets (mutate_ci.py plan reads TARGETS)
D = "src/default_term.jl"
I = "src/pl-incl.jl"
P = "src/pl-prims.jl"
F = "src/pl-fli.jl"
W = "src/pl-write.jl"
N = "src/pl-inline.jl"
H = "src/pl-termhash.jl"
C = "src/pl-comp.jl"
MUTANTS = [
    dict(id="BLOB-M1 isTextAtom admits a blob (pl-incl.h isTextAtom)", file=I, targets=TB,
         old="isTextAtom(t)::Bool = kind(t) === SYM && !is_reserved_symbol(t) && !is_blob(t)\n",
         new="isTextAtom(t)::Bool = kind(t) === SYM && !is_reserved_symbol(t)\n"),
    dict(id="BLOB-M2 a blob is keyed by its type NAME, not its handle (mk_blob)", file=D, targets=TB,
         old="        SYM, true, false, false, true, _blob_key(handle, rank), type_name, nothing,\n",
         new="        SYM, true, false, false, true, _blob_key(UInt64(length(string(type_name))), rank), type_name, nothing,\n"),
    dict(id="BLOB-M3 compareAtomsBlob: the type rank order is flipped (pl-prims.c compareAtoms type->rank)", file=P, targets=TB,
         old="    ra != rb && return _sign(ra - rb)\n",
         new="    ra != rb && return _sign(rb - ra)\n"),
    dict(id="BLOB-M4 PL_is_blob answers `text` for a blob (pl-fli.c PL_is_blob type)", file=F, targets=TB,
         old="    is_blob(a) && return string(blob_type(a))\n",
         new="    is_blob(a) && return \"text\"\n"),
    dict(id="BLOB-M5 the written form of a blob loses its `0x` address shape (pl-write.jl blob branch)", file=W, targets=TB,
         old="            \"<\" * string(blob_type(a)) * \">(0x\" * string(blob_handle(a); base=16) * \")\",\n",
         new="            \"<\" * string(blob_type(a)) * \">(#\" * string(blob_handle(a); base=16) * \")\",\n"),
    dict(id="BLOB-M6 _atom_word! has no blob branch (the compiler reads a blob as text)", file=N, targets=TB,
         old="    if is_blob(v)       # a blob's handle IS its atom word",
         new="    if false && is_blob(v)       # a blob's handle IS its atom word"),
    dict(id="BLOB-M7 charCode reads a blob as text (pl-fli.c charCode, PL_BLOB_TEXT)", file=F, targets=TB,
         old="        (is_reserved_symbol(w) || is_blob(w)) && return -1  # not PL_BLOB_TEXT\n",
         new="        (is_reserved_symbol(w)) && return -1  # not PL_BLOB_TEXT\n"),
    dict(id="BLOB-M8 termhash hashes a blob as `text` (pl-termhash.c type name)", file=H, targets=TB,
         old="                if is_blob(p)\n                    string(blob_type(p))\n",
         new="                if false && is_blob(p)\n                    string(blob_type(p))\n"),
    dict(id="BLOB-M9 the compiler treats a blob goal as callable (pl-comp.c isTextAtom(*arg))", file=C, targets=TB,
         old="        (is_reserved_symbol(goal) || is_blob(goal)) && return (goal, -1)  # isTextAtom(*arg): not `[]`, no blob\n",
         new="        (is_reserved_symbol(goal)) && return (goal, -1)  # isTextAtom(*arg): not `[]`, no blob\n"),
    dict(id="BLOB-M10 sym_hash of a blob is the type name's (all blobs of a type collide)", file=D, targets=TB,
         old="sym_hash(t::Term)::UInt64 = t.blob ? hash(t.key) : UInt64(objectid(t.name))",
         new="sym_hash(t::Term)::UInt64 = UInt64(objectid(t.name))"),
    dict(id="BLOB-M11 PL_is_callable on an atom reference admits a blob (pl-fli.c)", file=F, targets=TB,
         old="        return (!is_reserved_symbol(h) && !is_blob(h)) || is_nil(h)  # PL_BLOB_TEXT || ATOM_nil\n",
         new="        return (!is_reserved_symbol(h)) || is_nil(h)  # PL_BLOB_TEXT || ATOM_nil\n"),
    dict(id="BLOB-M12 the reference type's `show` of a blob drops the `0x` shape", file=D, targets=TB,
         old="            print(io, \"<\", t.name, \">(0x\", string(blob_handle(t); base=16), \")\")\n",
         new="            print(io, \"<\", t.name, \">(\", string(blob_handle(t); base=16), \")\")\n"),
    dict(id="BLOB-M13 blob_rank decodes the rank with the wrong sign", file=D, targets=TB,
         old="    t.blob ? -Int((t.key >> 3) & 0xffff) : throw(ArgumentError(\"blob_rank: not a blob\"))\n",
         new="    t.blob ? Int((t.key >> 3) & 0xffff) : throw(ArgumentError(\"blob_rank: not a blob\"))\n"),
    dict(id="BLOB-M14 compareAtomsBlob: two blobs of one type order by the reverse of the handle (D-0200)", file=P, targets=TB,
         old="    return ka == kb ? CMP_EQUAL : (ka < kb ? CMP_LESS : CMP_GREATER)\n",
         new="    return ka == kb ? CMP_EQUAL : (ka < kb ? CMP_GREATER : CMP_LESS)\n"),
]
