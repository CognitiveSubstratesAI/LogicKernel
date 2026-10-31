# ORIGINAL: T2's mutant list — no swipl-devel counterpart.
# tools/mutants/T2.py — the mutation battery of T2 (the string family: pl-string.c atom_string, string_x
# (string_codes, string_chars), text_to_string, string_code, get_string_code, split_string, string_bytes,
# read_string/5, read_string/3, open_string, text_chr, backSkipPadding, PL_text_recode, utf16_to_text; pl-prims.c
# sub_text for sub_string/5, string_length, string_concat), run ONCE, in CI (.github/workflows/mutation.yml; locally:
# tools/mutate.sh run). Format: tools/mutate_drive.py's (as MOD3b.py): `id`, `file`, `old` (must occur EXACTLY once),
# `new`, optional `equivalent` and `targets`. Killed by test/core_lang/test_string_swipl.jl (the rows st001-st214 and
# su001-su091 named in each id's KILL); verdicts: written by the battery, not yet run.
# The `old` strings are written in the repo's formatted style BEFORE `tools/warm.sh fmt` ran (the coding agent had no
# daemon): RE-FIT any that fmt rewraps (mutate_drive.py refuses a string that does not occur exactly once). Every `old`
# was checked to occur exactly once in src/pl-string.jl at wip/t2 (a text count, no Julia).
# Each KILL row was read from the pinned answers, not run on the kernel: a row that does not decide is a gap for the
# battery to show.
# NOT LISTED (each with its reason):
#   * _sub_state / _sub_state_n1 / _sub_state_n2 (the shifts and masks of the packed REDO_INT state): a wrong shift
#     makes the redo read another n1/n2 than it saved, so the enumeration of sub_string/5 repeats one candidate for ever
#     (a HANG, not a verdict); the masks only matter at 2^29 characters (SUB_STATE_LIMIT), a text no battery builds.
#   * text_chr's `c == chr && return i` (the offset): every caller compares the result with -1 only, so another offset
#     is EQUIVALENT (pl-string.jl text_chr callers: pl_split_string4_va, pl_read_string5_va, backSkipPadding).
#   * utf16_to_text's `w[i] > 0xff && (wide = true)`: a wide text of Latin-1 codes decodes to the same string, the
#     representation differs only (pl-string.jl utf16_to_text, the two returns), not an answer a row can see.
#   * string_bytes's `len % unit_length(enc) != 0`: unit_length is 1 for every encoding that reaches it (ENC_WCHAR is
#     refused at the top of pl_string_bytes3_va); an odd UTF-16 byte list is answered by utf16_to_text the same way.
#   * the encoding `text` (NotPortedError) and `ascii` decoding (refused by name): no rows, by design.
# TARGETS (audit D-0238): the step's own file first; the T1 file test/core_text/test_atom_text_swipl.jl shares
# text_chr, text_length, concat and the text conversions the string predicates run on.
TS = ["test/core_lang/test_string_swipl.jl"]
TA = ["test/core_text/test_atom_text_swipl.jl"]
TARGETS = TS + TA
W = "src/pl-string.jl"
MUTANTS = [
    # ── unify_text, atom_string, string_x ──
    dict(id="T2-A1 unify_text never accepts a text equal to the one in the term: atom_string(12, \"12\") fails (KILL st209, st210)",
         file=W, targets=TARGETS,
         old="return txt.encoding === tt.encoding &&",
         new="return false &&"),
    dict(id="T2-A2 atom_string builds a string where it should build the atom (KILL st037, st039, st050, st052, st054)",
         file=W, targets=TARGETS,
         old="return unify_text(ld, a, t, PL_ATOM) ? FTRUE : FFALSE",
         new="return unify_text(ld, a, t, PL_STRING) ? FTRUE : FFALSE"),
    dict(id="T2-A3 string_codes/string_chars answer a code list for both (KILL st073, st075, st079)",
         file=W, targets=TARGETS,
         old="return unify_text(ld, list, t::PL_chars_t, out_type)",
         new="return unify_text(ld, list, t::PL_chars_t, PL_CODE_LIST)"),
    # ── sub_text (sub_string/5) ──
    dict(id="T2-B1 sub_string with a given length equal to the text's: the guard `l > la` is `>=` (KILL st211)",
         file=W, targets=TARGETS,
         old="l > la && return FFALSE",
         new="l >= la && return FFALSE"),
    dict(id="T2-B2 sub_string with a given sub text and after: the offset is one too far (KILL st134)",
         file=W, targets=TARGETS,
         old="off = la - a - ls",
         new="off = la - a - ls + 1"),
    dict(id="T2-B3 sub_string with only `after` given ends one candidate early (KILL st212)",
         file=W, targets=TARGETS,
         old="outcome = l > 0 ? 0 : (match ? 1 : 2)",
         new="outcome = l > 1 ? 0 : (match ? 1 : 2)"),
    dict(id="T2-B4 sub_string(+, -, -, -, -) ends before the empty tail substring (KILL st137, st139, st166)",
         file=W, targets=TARGETS,
         old="if b == la",
         new="if b == la - 1"),
    # ── string_code/3, get_string_code/3, PL_error_range, text_code_at ──
    dict(id="T2-C1 string_code(+Index, …) reads the code one position early (KILL st171, st172, st179, st180)",
         file=W, targets=TARGETS,
         old="c = i == 0 ? nothing : text_code_at(t, i - 1)",
         new="c = i == 0 ? nothing : text_code_at(t, i)"),
    dict(id="T2-C2 text_code_at accepts the index one past the end (KILL st174, st198)",
         file=W, targets=TARGETS,
         old="(u == -1 || u >= t.length) && return nothing",
         new="(u == -1 || u > t.length) && return nothing"),
    dict(id="T2-C3 PL_error_range swaps the bounds of range(Low, High) (KILL st198)",
         file=W, targets=TARGETS,
         old="PL_cons_functor(ld, r, _err_functor(ld, :range, 2), low, high)",
         new="PL_cons_functor(ld, r, _err_functor(ld, :range, 2), high, low)"),
    # ── split_string/4, text_chr ──
    dict(id="T2-D1 split_string never skips the padding in front of a field (KILL st004, st005, st010, st011)",
         file=W, targets=TARGETS,
         old="if skip ",
         new="if false "),
    dict(id="T2-D2 split_string: `sep_at == en` is `>=` — EQUIVALENT", file=W, targets=TARGETS,
         old="sep_at == en && break",
         new="sep_at >= en && break",
         equivalent="src/pl-string.jl:pl_split_string4_va — read, not run: `sep_at` is `i` after the `while i < en` search "
                    "loop, which only increments `i` while it is below `en`, and `i <= en` on entry (set by the padding skip "
                    "or `i = sep_at + 1` with `sep_at < en`), so `sep_at > en` cannot happen and `>=` is `==`."),
    dict(id="T2-D3 split_string treats a separator that follows a separator as padding to skip (KILL st213)",
         file=W, targets=TARGETS,
         old="text_chr(sep, next_chr) != -1",
         new="text_chr(sep, next_chr) == -1"),
    dict(id="T2-D4 text_chr finds no NUL: a NUL in the input is not a separator or padding any more (KILL st012)",
         file=W, targets=TARGETS,
         old="return chr == 0 ? t.length : -1",
         new="return -1"),
    # ── string_bytes/3, utf16_to_text, PL_text_recode ──
    dict(id="T2-E1 string_bytes accepts the encoding wchar_t (KILL su023, su054)",
         file=W, targets=TARGETS,
         old="if enc === ENC_UNKNOWN || enc === ENC_WCHAR",
         new="if enc === ENC_UNKNOWN"),
    dict(id="T2-E2 string_bytes: the byte count multiplies by unit_length — EQUIVALENT", file=W, targets=TARGETS,
         old="n = txt.length * unit_length(txt.encoding)",
         new="n = txt.length",
         equivalent="src/pl-string.jl:pl_string_bytes3_va with PL_text_recode — read, not run: PL_text_recode leaves the text in "
                    "ENC_UTF8, ENC_ISO_LATIN_1, ENC_OCTET, ENC_ASCII, ENC_UTF16LE or ENC_UTF16BE (and returns early when the "
                    "encoding already matches), and unit_length is 1 for each of them (it is 4 only for ENC_WCHAR, refused "
                    "at the top of the predicate), so the product is the length."),
    dict(id="T2-E3 UTF-16 decode reads the two bytes of a unit in the other order (KILL su035, su036, su038, su055)",
         file=W, targets=TARGETS,
         old="w[i] = be ? (b0 << 8) | b1 : (b1 << 8) | b0",
         new="w[i] = be ? (b1 << 8) | b0 : (b0 << 8) | b1"),
    dict(id="T2-E4 UTF-16 decode takes any unit after a lead surrogate for its trail (KILL su040)",
         file=W, targets=TARGETS,
         old="if i + 1 <= len && IS_UTF16_TRAIL(w[i + 1])",
         new="if true"),
    dict(id="T2-E5 PL_text_recode lets a wide text pass to Latin-1, octet or ascii (KILL su006, su007, su008)",
         file=W, targets=TARGETS,
         old="text.encoding === ENC_WCHAR && return text_representation_error(ld, encoding)",
         new="false && return text_representation_error(ld, encoding)"),
    # ── read_string/5, read_string/3, open_string/2, backSkipPadding ──
    dict(id="T2-F1 read_string/5 keeps the padding in front: the skip loop stops at the first padding character (KILL su075, su081, su082)",
         file=W, targets=TARGETS,
         old="while chr != EOF && text_chr(pad, chr) != -1",
         new="while chr != EOF && text_chr(pad, chr) == -1"),
    dict(id="T2-F2 read_string/5 ends at the first character that is not a delimiter (KILL su074, su078, su090)",
         file=W, targets=TARGETS,
         old="(chr == EOF || text_chr(sep, chr) != -1) && break",
         new="(chr == EOF || text_chr(sep, chr) == -1) && break"),
    dict(id="T2-F3 backSkipPadding steps one byte, not one character, back over a multibyte padding character (KILL su091; the battery decides)",
         file=W, targets=TARGETS,
         old="        stop = e\n",
         new="        stop = stop - 1\n"),
    dict(id="T2-F4 read_string/3 reads one character more than asked (KILL su056, su063)",
         file=W, targets=TARGETS,
         old="while count < len",
         new="while count <= len"),
    dict(id="T2-F5 open_string leaves a wide text as it is: the stream reads its UTF-32 bytes (KILL su064, su065)",
         file=W, targets=TARGETS,
         old="text.encoding === ENC_ISO_LATIN_1 || PL_mb_text(text, REP_UTF8)",
         new="true || PL_mb_text(text, REP_UTF8)"),
]
