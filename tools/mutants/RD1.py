# ORIGINAL: RD1's mutant list — no swipl-devel counterpart.
# tools/mutants/RD1.py — the mutation battery of RD1 (pl-read.c's stream-reading predicates: read_term/3,2 `pl_read_term3_va`,
# `pl_read_term2_va`, `$is_named_var/1` `pl_is_named_var1_va`, `pl_raw_read2`, `pl_raw_read`, `pl_read2`, `pl_read`, as registered in
# src/pl-read.jl and src/pl-ext.jl), run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format:
# tools/mutate_drive.py's (as MOD3b.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# Killed by test/core_text/test_read_stream_swipl.jl (rows rt01-rt219, rt300-rt321 named in each id's KILL). Verdicts: written by the
# battery, not yet run. RD1 is Tier 3 (registration, argument checks, error terms; no engine/reader/writer code): the battery is
# advisory, the root suite is the gate.
# The `old` strings are written in the repo's formatted style BEFORE `tools/warm.sh fmt` ran (the coding agent had no daemon):
# RE-FIT any that fmt rewraps (mutate_drive.py refuses a string that does not occur exactly once). Every `old` was checked to occur
# exactly once in its file at wip/rd1 (a text count, no Julia).
# NOT LISTED (each with its reason):
#   * the reader itself (`read_term`, `raw_read`, `read_term_from_stream`'s option scan): the mutants of those are R1's and LB1's;
#     this list holds the RD1 wrappers only.
#   * the rows that read standard input (rt21-rt26, rt170, rt171) are UNVERIFIED on the kernel: a KILL named for one of them holds
#     only if stdin is at end-of-file in the battery's run (tools/run_tests.sh uses < /dev/null).
# TARGETS (audit D-0238): the wrappers are reached by Prolog goals only through test_read_stream_swipl.jl: a text search of test/
# for `read_term(`, `raw_read`, `is_named_var`, `pl_read2` and `pl_read_term` finds the other files in the reader's family
# (test_read_swipl.jl calls the Julia `raw_read` function, test_compiler_warnings_swipl.jl `atom_is_named_var` through the style
# check, test_read.jl the term_to_atom family) and they are listed where the mutated line is the shared reader code; none of
# the mutants below is in shared code.
TS = ["test/core_text/test_read_stream_swipl.jl"]
TARGETS = TS   # the baseline's (mutate_ci.py plan reads TARGETS)
W = "src/pl-read.jl"
X = "src/pl-ext.jl"
TB = TS + ["test/core_text/test_read.jl", "test/core_text/test_read_term_swipl.jl"]


def m(id, old, new, targets=TS, equivalent=None, file=W):
    d = dict(id=id, file=file, old=old, new=new, targets=targets)
    if equivalent is not None:
        d["equivalent"] = equivalent
    return d


MUTANTS = [
    # ── pl-read.c pl_raw_read2 ──
    m("RD1-A1 $raw_read keeps the full stop: the text ends `.` (KILL rt172, rt177, rt183, rt195)",
      "    if chr == Int('.')\n", "    if false\n"),
    m("RD1-A2 $raw_read does not strip the layout before the full stop (KILL rt172, rt177, rt193)",
      "        top = backSkipBlanks(b, s, t2)\n", "        top = t2\n"),
    m("RD1-A3 $raw_read keeps the leading layout (comments are blanks) (KILL rt174, rt199)",
      "    s = skipSpaces(b, s)\n", "    nothing\n"),
    m("RD1-A4 $raw_read's `0' .` guard does not give the space back (KILL rt173)",
      "        top += 1\n    end\n    s = skipSpaces(b, s)", "        nothing\n    end\n    s = skipSpaces(b, s)"),
    m("RD1-A5 $raw_read's `0'` guard asks for one character before the end only at `top - 2 > s` (KILL rt173)",
      "top - 2 >= s &&", "top - 2 > s &&"),
    m("RD1-A6 $raw_read's `0'` guard tests the quote byte for inequality (KILL rt173, rt197)",
      "_byte(b, top - 1) == Int('\\'')", "_byte(b, top - 1) != Int('\\'')"),
    m("RD1-A7 $raw_read's `0'` guard tests for another digit than 0 (KILL rt173)",
      "_byte(b, top - 2) == Int('0')", "_byte(b, top - 2) == Int('1')"),
    m("RD1-A8 $raw_read fails where it raises the syntax error (KILL rt185, rt186, rt187)",
      "return PL_raise_exception(ld, rd.exception) ? FTRUE : FFALSE   # PL_release_stream(in)", "return FFALSE"),
    m("RD1-A9 $raw_read takes a stream error for a syntax error: the status test is inverted (KILL rt185, rt186)",
      "if Sferror(in) != 0", "if Sferror(in) == 0"),
    m("RD1-A10 $raw_read/1 reads from the stream named by its own argument, not the current input (KILL rt171)",
      "pl_raw_read(ld::PL_local_data{T}, term::term_t) where {T} = pl_raw_read2(ld, 0, term)",
      "pl_raw_read(ld::PL_local_data{T}, term::term_t) where {T} = pl_raw_read2(ld, term, term)"),
    # ── pl-read.c pl_read2, pl_read ──
    m("RD1-B1 read/2 does not raise the reader's syntax error: the read fails (KILL rt15, rt104, rt105, rt107)",
      "    if rd.has_exception\n        rval = PL_raise_exception(ld, rd.exception)", "    if false\n        rval = PL_raise_exception(ld, rd.exception)"),
    m("RD1-B2 read/1 reads from the stream named by its own argument (KILL rt21)",
      "pl_read(ld::PL_local_data{T}, term::term_t) where {T} = pl_read2(ld, 0, term)",
      "pl_read(ld::PL_local_data{T}, term::term_t) where {T} = pl_read2(ld, term, term)"),
    m("RD1-B3 read/2 takes the inverted stream status test: a healthy stream's read always succeeds (KILL rt06, rt19, rt20)",
      "Sferror(s) != 0 && return streamStatus(ld, s) ? FTRUE : FFALSE      # else PL_release_stream(s)",
      "Sferror(s) == 0 && return streamStatus(ld, s) ? FTRUE : FFALSE      # else PL_release_stream(s)"),
    # ── pl-read.c read_term/3 and read_term/2 ──
    m("RD1-C1 read_term/3 reads the options into the term and the term into the options (KILL rt30, rt31, rt130)",
      "read_term_from_stream(gd, ld, s, A2, A3) && return FTRUE", "read_term_from_stream(gd, ld, s, A3, A2) && return FTRUE"),
    m("RD1-C2 read_term/3 reads from the current input, not the stream named (KILL rt30, rt71, rt72, rt75)",
      "s = getTextInputStream(ld, A1)\n    s === nothing && return FFALSE\n    read_term_from_stream(gd, ld, s, A2, A3)",
      "s = getTextInputStream(ld, 0)\n    s === nothing && return FFALSE\n    read_term_from_stream(gd, ld, s, A2, A3)"),
    m("RD1-C3 read_term/2 swaps the term and the options (KILL rt23, rt25, rt26)",
      "read_term_from_stream(gd, ld, s, A1, A2) && return FTRUE", "read_term_from_stream(gd, ld, s, A2, A1) && return FTRUE"),
    m("RD1-C4 read_term/2 names its first argument as the stream, not the current input (KILL rt23, rt24, rt25)",
      "getTextInputStream(ld, 0)\n    s === nothing && return FFALSE\n    read_term_from_stream(gd, ld, s, A1, A2)",
      "getTextInputStream(ld, A1)\n    s === nothing && return FFALSE\n    read_term_from_stream(gd, ld, s, A1, A2)"),
    # ── pl-read.c is_named_var ──
    m("RD1-D1 $is_named_var also holds for the names the style check marks as not named (-1, 0) (KILL rt201, rt202, rt203, rt204, rt213, rt216)",
      "atom_is_named_var(codeunits(sym_text(name))) == 1 ? FTRUE : FFALSE", "atom_is_named_var(codeunits(sym_text(name))) != 0 ? FTRUE : FFALSE"),
    m("RD1-D2 $is_named_var on a non-atom goes on with no atom (KILL rt208, rt209, rt210, rt211)",
      "    name === nothing && return FFALSE\n    return atom_is_named_var", "    return atom_is_named_var"),
    # ── the registrations: the ISO flag is read by predicate_property/2 and the ISO-mode checks, no row calls those ──
    m("RD1-E1 read_term/3 is registered without PL_FA_ISO",
      'PL_extension("read_term", 3, pl_read_term3_va, PL_FA_ISO | PL_FA_VARARGS),', 'PL_extension("read_term", 3, pl_read_term3_va, PL_FA_VARARGS),',
      equivalent="read, not run: the flag is read by predicate_property(P, iso) and the ISO-mode checks; no row of the rows file calls either"),
    m("RD1-E2 read/1 is registered without PL_FA_ISO",
      'PL_extension("read", 1, pl_read, PL_FA_ISO),', 'PL_extension("read", 1, pl_read, 0x00),', file=X,
      equivalent="read, not run: the same as RD1-E1"),
    # ── pl-read.c blob(Type): atom_to_blob_mode_ex, blob_syntax_available, blob_name_char, scan_blob_name, the tokeniser's `<` ──
    # (the tokeniser is shared reader code: TARGETS also hold the other reader test files, audit D-0238)
    m("RD1-F1 the tokeniser claims `<type>(` in every mode, blob(error) included (KILL rt314, rt317)",
      "c == Int('<') && !must_be_op && rd.blobs !== :error && blob_syntax_available(rd)",
      "c == Int('<') && !must_be_op && blob_syntax_available(rd)",
      targets=TB),
    m("RD1-F2 the tokeniser claims `<type>(` where an operator is expected (KILL rt315)",
      "c == Int('<') && !must_be_op && rd.blobs !== :error",
      "c == Int('<') && rd.blobs !== :error",
      targets=TB),
    m("RD1-F3 `<type>(` is claimed in a module where `<` is a prefix operator (KILL rt311)",
      "    ok, _, _ = currentOperator(gd, gd.modules[rd.module_], mk_sym(T, :<), OP_PREFIX)    # ATOM_smaller\n    return !ok",
      "    ok, _, _ = currentOperator(gd, gd.modules[rd.module_], mk_sym(T, :<), OP_PREFIX)    # ATOM_smaller\n    return ok || true",
      targets=TB),
    m("RD1-F4 the type name does not take `-` (KILL rt320, rt321)",
      "PlIdContW(c) || c == Int('-') || c == Int('.')",
      "PlIdContW(c) || c == Int('.')",
      targets=TB),
    m("RD1-F5 an empty type name `<>(` is a blob (KILL rt310)",
      "(e == in || _byte(b, e + 1) != Int('(')) && return nothing",
      "_byte(b, e + 1) != Int('(') && return nothing",
      targets=TB),
    m("RD1-F6 `<type>` not followed by `(` is a blob (KILL rt316)",
      "(e == in || _byte(b, e + 1) != Int('(')) && return nothing",
      "e == in && return nothing",
      targets=TB),
    m("RD1-F7 blob(dead) is read as blob(error) (KILL rt320)",
      "        rd.blobs = :dead\n",
      "        rd.blobs = :error\n"),
    m("RD1-F8 blob(resolve) is read as blob(error) (KILL rt321)",
      "        rd.blobs = :resolve\n",
      "        rd.blobs = :error\n"),
    m("RD1-F9 another atom as the blob mode is accepted (KILL rt307, rt318)",
      "        return PL_put_atom(ld, v, a) && PL_error(ld, ERR_DOMAIN, mk_sym(T, :blob), v)\n",
      "        return true\n"),
    m("RD1-F10 read_term's blob option is never applied (KILL rt307, rt320, rt321)",
      "    opt_blobs !== nothing && !atom_to_blob_mode_ex(ld, rd, opt_blobs::T) && return false\n",
      "    opt_blobs !== nothing && false && return false\n"),
    m("RD1-F11 read_clause's blob option is never applied (KILL rt318)",
      "            if opt_blobs !== nothing && !atom_to_blob_mode_ex(ld, rd, opt_blobs::T)\n",
      "            if false && !atom_to_blob_mode_ex(ld, rd, opt_blobs::T)\n"),
    m("RD1-F12 the read data starts in blob(dead) mode (KILL rt317)",
      "        :error,                                     # blobs (RD_BLOB_ERROR)\n",
      "        :dead,                                      # blobs (RD_BLOB_ERROR)\n",
      targets=TB),
]
