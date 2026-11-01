# ORIGINAL: O1B's mutant list — no swipl-devel counterpart.
# tools/mutants/O1B.py — the mutation battery of O1B (the output redirect of pl-file.c: setStandardStream,
# pushOutputContext, popOutputContext, redir_context, setupOutputRedirect, closeOutputRedirect, discardOutputRedirect,
# with_output_to/2, tellString, toldString in src/os/pl-file.jl; pl-pro.c callProlog's `ex` out-argument), run ONCE,
# in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as MOD3b.py):
# `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`. Killed by
# test/core_lang/test_with_output_to_swipl.jl (rows w01-w72, named in each id's KILL); a row marked UNVERIFIED in that
# file (w43 w44 w64 w68 w69 w70) is never the only kill of a mutant here. Verdicts: written by the battery, not yet run.
# The `old` strings are written in the repo's formatted style BEFORE `tools/warm.sh fmt` ran (the coding agent had no
# daemon): RE-FIT any that fmt rewraps (mutate_drive.py refuses a string that does not occur exactly once). Every `old`
# was checked to occur exactly once in its file at wip/o1b (a text count, no Julia). Anchors that must tell the close
# path from the discard path span two or more lines (the two functions share their opening lines).
# NOT LISTED (each with its reason):
#   * popOutputContext's `s.magic != SIO_MAGIC` branch (the output waiting on the stack was closed meanwhile): no row closes
#     the stream that waits; the branch is upstream's guard against a closed current output (DIVERGES there: no Sdprintf
#     message). NOT COVERED by a row, left to a later row, not claimed equivalent.
#   * pushOutputContext's `Sacquire(cur)` and popOutputContext's `Srelease(c)`: the stream layer here counts only
#     (pl-redirect.jl header: the locks are NOT PORTED); the count is read by no row.
# TARGETS (audit D-0238): each mutant lists every test file that exercises its mutated code. with_output_to/2 is called
# by test_with_output_to_swipl.jl (the step's own file, first) and, as a helper in the Prolog text of their rows, by
# test_write_swipl.jl:197, test_read_term_swipl.jl:392, test_builtins_swipl.jl:235/240, test_head_code_swipl.jl:144 and
# test_blob.jl:110. format/3 (O1-A, pl-fmt.jl) shares setupOutputRedirect, closeOutputRedirect, discardOutputRedirect and
# tellString/toldString: test_format_swipl.jl (O1-A's rows file, NOT on disk when this list was written). The first
# battery run prunes a target that does not pass on the unmutated tree (a file that still needs a not yet ported
# predicate), as the driver refuses a baseline that fails.
TS = ["test/core_lang/test_with_output_to_swipl.jl"]
TF = ["test/core_lang/test_format_swipl.jl"]                      # O1-A's rows (format/3 and the column handling)
TU = [                                                            # users of with_output_to/2 in their Prolog text
    "test/core_text/test_write_swipl.jl", "test/core_text/test_read_term_swipl.jl", "test/foreign/test_builtins_swipl.jl",
    "test/compile/test_head_code_swipl.jl", "test/core_lang/test_blob.jl",
]
TSA = ["test/core_lang/test_cleanup_swipl.jl", "test/core_lang/test_context_module_swipl.jl", "test/foreign/test_query_answers.jl"]
REDIR = TS + TF + TU
TARGETS = TS + TF + TU + TSA        # the baseline's (mutate_ci.py plan reads TARGETS)
R = "src/os/pl-file.jl"
P = "src/pl-pro.jl"

# The two functions share their opening lines: the anchors run on to the line that differs.
CLOSE_POP = "    ctx.redirected && popOutputContext(ld)\n\n    s = ctx.stream::IOSTREAM\n    if ctx.is_stream\n        rval = streamStatus(ld, s)\n"
DISCARD_POP = "    ctx.redirected && popOutputContext(ld)\n\n    s = ctx.stream::IOSTREAM\n    if ctx.is_stream\n        streamStatus(ld, s)\n"

MUTANTS = [
    # ── closeOutputRedirect, discardOutputRedirect ──
    dict(id="O1B-A1 closeOutputRedirect does not pop the output context: the current output stays the closed memory stream (KILL w51, w39)",
         file=R, targets=REDIR,
         old=CLOSE_POP,
         new=CLOSE_POP.replace("    ctx.redirected && popOutputContext(ld)\n", "    nothing\n")),
    dict(id="O1B-A2 discardOutputRedirect does not pop the output context: after a failed goal the output stays redirected (KILL w39, w41)",
         file=R, targets=REDIR,
         old=DISCARD_POP,
         new=DISCARD_POP.replace("    ctx.redirected && popOutputContext(ld)\n", "    nothing\n")),
    dict(id="O1B-A3 setupOutputRedirect does not push the output context: the goal writes to the real output, the sink stays empty (KILL w01, w13)",
         file=R, targets=REDIR,
         old="    redir && pushOutputContext(ld, ctx.stream::IOSTREAM)\n",
         new="    nothing\n"),
    dict(id="O1B-A4 setupOutputRedirect does not set the magic: closeOutputRedirect returns at once, the sink stays unbound (KILL w01, w51)",
         file=R, targets=REDIR,
         old="    ctx.magic = REDIR_MAGIC\n\n    redir &&",
         new="    ctx.magic = 0\n\n    redir &&"),
    dict(id="O1B-A5 closeOutputRedirect: Sclose(s) == 0 inverted: the text is never unified (KILL w01, w03)",
         file=R, targets=REDIR,
         old="        if Sclose(s) == 0\n",
         new="        if Sclose(s) != 0\n"),
    dict(id="O1B-A6 closeOutputRedirect drops the unification of the difference list's tail with its diff (KILL w05, w06, w11, w12)",
         file=R, targets=TS,
         old="                rval = PL_unify(ld, tail, diff)\n",
         new="                rval = true\n"),
    dict(id="O1B-A7 the bytes unified are the whole buffer, not its first size[] bytes: NULs follow the text (KILL w13, w22, w23)",
         file=R, targets=REDIR,
         old="(b === nothing || ctx.size[] == 0) ? UInt8[] : b[1:ctx.size[]]",
         new="(b === nothing || ctx.size[] == 0) ? UInt8[] : b"),
    dict(id="O1B-A8 the text is declared ISO Latin-1, not UTF-8: wide characters are mangled (KILL w19, w20, w21)",
         file=R, targets=TS,
         old="length(String(copy(bytes))), ENC_UTF8, false)",
         new="length(String(copy(bytes))), ENC_ISO_LATIN_1, false)"),
    dict(id="O1B-A9 the memory stream is written ISO Latin-1, not UTF-8: a character above 255 is not written whole (KILL w19, w20, w21)",
         file=R, targets=TS,
         old="        stream.encoding = ENC_UTF8\n",
         new="        stream.encoding = ENC_ISO_LATIN_1\n"),
    # ── setupOutputRedirect: the sink kinds ──
    dict(id="O1B-B1 codes(C) is a character list (KILL w03, w09)", file=R, targets=TS,
         old="(T, :codes), 1)\n            ctx.out_format = PL_CODE_LIST\n",
         new="(T, :codes), 1)\n            ctx.out_format = PL_CHAR_LIST\n"),
    dict(id="O1B-B2 codes(C, T) has no tail: out_arity 1, the list is closed with [] (KILL w05, w11)", file=R, targets=TS,
         old="(T, :codes), 2)\n            ctx.out_format = PL_CODE_LIST\n            ctx.out_arity = 2\n",
         new="(T, :codes), 2)\n            ctx.out_format = PL_CODE_LIST\n            ctx.out_arity = 1\n"),
    dict(id="O1B-B3 string(S) is made an atom: string(abc) unifies with the text abc (KILL w31, w02)", file=R, targets=TS,
         old="(T, :string), 1)\n            ctx.out_format = PL_STRING\n",
         new="(T, :string), 1)\n            ctx.out_format = PL_ATOM\n"),
    dict(id="O1B-B4 the type error of a bad sink names `stream`, not `output` (KILL w61, w67)", file=R, targets=TS,
         old="PL_error(ld, ERR_TYPE, mk_sym(T, :output), to)",
         new="PL_error(ld, ERR_TYPE, mk_sym(T, :stream), to)"),
    dict(id="O1B-B5 the alias `user` is not recognised: it is looked up as a stream name and raises (KILL w54)", file=R, targets=TS + TF,
         old="    elseif a !== nothing\n        if isTextAtom(a) && sym_key(a) == sym_key(mk_sym(T, :user))\n            uo = Suser_output(ld)",
         new="    elseif a !== nothing\n        if isTextAtom(a) && sym_key(a) == sym_key(mk_sym(T, :usr))\n            uo = Suser_output(ld)"),
    dict(id="O1B-B6 an output stream is refused as no output stream: the permission test inverted (KILL w55, w56)", file=R, targets=TS + TF,
         old="            if (s.flags & SIO_OUTPUT) == 0\n",
         new="            if (s.flags & SIO_OUTPUT) != 0\n"),
    # ── with_output_to/2 ──
    dict(id="O1B-C1 with_output_to/2 closes the redirect also after a failed goal: the sink is unified, it succeeds (KILL w37, w25)",
         file=R, targets=REDIR,
         old="        if rval\n            return closeOutputRedirect",
         new="        if true\n            return closeOutputRedirect"),
    dict(id="O1B-C2 with_output_to/2 does not discard the redirect after a failed or raised goal (KILL w39, w41, w40)",
         file=R, targets=REDIR,
         old="        discardOutputRedirect(ld, outctx)\n",
         new="        nothing\n"),
    dict(id="O1B-C3 with_output_to/2 does not re-raise the goal's exception: it fails (KILL w40, w42, w48)",
         file=R, targets=REDIR,
         old="            PL_raise_exception(ld, ex[])\n",
         new="            nothing\n"),
    # ── tellString, toldString (format/2's column handling; ~@) ──
    dict(id="O1B-D1 toldString does not pop the output context of a memory stream (KILL O1-A's column / ~@ rows in test_format_swipl.jl: after the first the current output is a closed stream)",
         file=R, targets=TF + TS,
         old="    if s.functions == Smemfunctions\n",
         new="    if s.functions != Smemfunctions\n"),
    dict(id="O1B-D2 tellString leaves the stream's encoding at its default: the enc argument is dropped (KILL O1-A's wide-character ~@/column rows in test_format_swipl.jl)",
         file=R, targets=TF + TS,
         old="    stream.encoding = enc\n",
         new="    nothing\n"),
    # ── pl-pro.c callProlog, the `ex` out-argument ──
    dict(id="O1B-E1 callProlog leaves ex empty after a failed query: the exception is swallowed, with_output_to/2 fails (KILL w40, w42)",
         file=P, targets=TS + TSA,
         old="    if !rval && ex !== nothing\n",
         new="    if false\n"),
    # ── EQUIVALENT ──
    dict(id="O1B-Q1 closeOutputRedirect without the `already done` guard (EQUIVALENT)",
         file=R, targets=TS,
         old="    ctx.magic != REDIR_MAGIC && return rval             # already done\n",
         new="    nothing\n",
         equivalent="src/os/pl-file.jl:pl_with_output_to2_va — read, not run: the only caller here calls EITHER closeOutputRedirect OR discardOutputRedirect, once, on a context whose magic setupOutputRedirect just set; the guard is reached only by a second call. O1-A's format/3 calls one of the two once, as upstream (pl-fmt.c)."),
    dict(id="O1B-Q2 setStandardStream without the `old !== s` guard (EQUIVALENT)",
         file=R, targets=TS,
         old="    if old !== s\n",
         new="    if true\n",
         equivalent="src/os/pl-file.jl:setStandardStream — read, not run: for old === s the body takes a reference to s (Sacquire), stores s again and releases the old one (the same s): the count is unchanged, and no row reads it (the stream layer counts only, header NOT PORTED)."),
]
