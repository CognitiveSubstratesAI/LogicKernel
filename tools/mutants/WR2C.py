# ORIGINAL: WR2's mutant list — no swipl-devel counterpart.
# tools/mutants/WR2C.py — the mutation battery of WR2 (the rebase of WR2 onto the JET gateway fix: gate/wr2c, mutants/WR2C; the ids stay WR2-n) (R2: the writer's second part — write_term/2,3's `integer_format` and `float_format`
# options through do_format (pl-write.c writeNumber, src/pl-write.jl writeNumber + `_write_number_format`), the `blobs(portray)` branch of
# writeAtom with callPortray's halt check (pl-write.c writeAtom/callPortray, pl-write.jl), and PL_get_text's CVT_WRITE, CVT_WRITEQ and
# CVT_WRITE_CANONICAL conversions (pl-text.c `case_write`, src/os/pl-text.jl `_get_text_write`); audit D-0457). Run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). The format is tools/mutate_drive.py's: `id`, `file`, `old` (must occur
# EXACTLY once), `new`, optional `equivalent` and `targets`. NOT RUN YET (written edit-only, 2026-11-09, at the gated candidate
# gate/wr2c): the KILL named in each id is the assertion that is DESIGNED to fail; the first CI battery replaces this header with the result.
# VERDICT POLICY: WR2 is not boot-path code (nothing here runs while the template of `PL_global_data{T}()` is built), so a warm-daemon verdict
# stands for it, and the fresh-process verdicts of the CI battery (`tools/mutate_ci.py one`) are authoritative either way.
# Each id names its KILL (file:line at the gated candidate):
#   TW = test/core_text/test_wr2_swipl.jl. THE ROWS: the loop of the first testset, TW:190 `@test (i, kl[i]) == (i, expected[i])`, compares the kernel's
#   line of each row tN with test_wr2_swipl.out (swipl 10.1.20's own, and TW:197 re-checks it live); a row is cited as `tN`, its source in
#   test_wr2_swipl.pl. THE CVT ROWS: the loop of the second testset, TW:370, compares each row rN of test_wr2_cvt_swipl.out; rN = (term - 1) * 3 + 1
#   (write), + 1 (writeq), + 2 (write_canonical) for the 36 ASCII terms of `_CVT_ASCII` (TW:235-243). THE KERNEL ROWS: TW:391, 392, 393, 397, 399 (and the literal rows 406, 411).
#   TWS = test/core_text/test_write_swipl.jl (the hand corpus of text_corpora_testlib.jl compared with swipl, TWS:267-276, 362-367: "a- -1", "1 - -1");
#   TFW = test/core_text/test_float_write_swipl.jl (TFW:207-219: "- -1.5", "a- -2.5e-07", "- -0.0"); TWF = test/core_text/test_write_family_swipl.jl
#   (portray(true), portray_goal, blobs(portray) rows, :203-345); TWC = test/core_lang/test_write_cells.jl (portray(true) rows, :119-120).
# EQUIVALENT, each with its code reason (it must SURVIVE; a target that catches it proves the claim wrong and blocks):
#   * WR2-N5, WR2-N6: the default formats routed through do_format: `~d` (arg default 0, src/os/pl-fmt.jl:554-555) and `~h` (default 3 digits, :1354-1389,
#     `format_float(f.f, 3, 'e')`) are what the fast path of writeNumber computes (pl-write.jl:1007-1022, 1033-1035); the fast path is a kept DIVERGES
#     (the hot path), not a different text;
#   * WR2-P6: `is_reserved_symbol(a) ||` in the blob test: the one reserved symbol of the kernel is `[]` (src/pl-ressymbol.jl:12-17: dict, trienode, ... are not
#     ported), and `!is_nil(a)` (src/pl-write.jl:869) excludes it, so `is_blob(a)` alone selects the same atoms;
#   * WR2-P11: the halt test of writeAtom: callPortray repeats it (src/pl-write.jl:1318, `gd.halt_cleaning > CLN_PROLOG && return 0`), so no portray call is made and
#     the fall-through writes the blob either way (the one difference is the foreign frame and the term reference opened first);
#   * WR2-T6: PL_WRT_NODOTINATOM of CVT_WRITE_CANONICAL: no code of src/ reads the flag (its uses: the constant, SWI-Prolog.jl:239; the flag set, pl-write.jl:2471 and
#     pl-text.jl:70), the `dot_in_atom` test of pl-write.c:514, 598 is not ported;
#   * WR2-T11: `numberVars` ignoring NV_ERROR: with `numbered_check` false and `AV_SKIP` its three error results (src/pl-prims.jl:523-526, 549-563: a number out of the
#     tagged range, an attributed variable under AV_ERROR, an already numbered term) are unreachable (the offset is 0 and the walk has no 2^60 variables);
#   * WR2-T16: `fd.encoding = ENC_UTF8`: `Sopenmem(..., "w")` makes a SIO_TEXT stream (pl-stream.jl:1300) and `Snew` gives a SIO_TEXT stream ENC_UTF8 (pl-stream.jl:1094).
# THE LATER ROWS (added at the gated candidate after the first list; each mutant's id names its KILL): t64, t65, t66, t67 of the .pl (N11, N17, P14, C1/C2),
#   the HALT TESTSET TW:216-230 (gd.halt_cleaning raised before t48 and t67: C1 at TW:228, C2 and P12 at TW:223), and the kernel rows TW:393 (T19, the `canonical` field),
#   TW:406 (T9, a LITERAL `'é'('λ')`: no oracle, write_canonical/1 adds pattern_syntax_solo) and TW:411 (T13, a LITERAL [97,0]). The rows with no oracle value
#   (C1, C2, P12, T9, T13, T19) say why in the test's comment; swipl cannot be put into its halt sequence, nor asked what PL_get_text writes (only the CVT equivalent).
# NOT MUTATED (no code reason found to call them equivalent, no row to expect): the foreign frame of writeAtom's portray branch (PL_open_foreign_frame/PL_close_foreign_frame:
# a leaked frame is seen by no row); `Sclose(fd)` of `_get_text_write`; the module index `options.m.index` passed to do_format (read by ~p/~@ only); the `on_attvar = AV_SKIP`
# of the numbering (no row holds an attributed variable: AV10's); `singletons` forced 1 on a cyclic term (no cyclic term in the corpus).
# TARGETS (audit D-0238): every test file that runs the mutated code and can see its effect. The format-path rows of writeNumber (integer_format/float_format other than the
# defaults) run in TW only: no other test file passes the options (TWF:269 holds a comment on float_format, no row). The default-path rows of writeNumber run in every
# writer test: TW, TWS, TFW, TWF, TWC. callPortray and the blobs(portray) branch of writeAtom run in the portray rows of TW, TWF, TWS, TWC and
# test_context_module_swipl.jl/test_metacall.jl (portray_goal through call/3). PL_get_text's CVT_WRITE* run in TW only: no other test or src caller passes the flags
# (CVT_WRITE appears in src/ only in pl-text.jl and the constants). NOT listed: test_format_swipl.jl (do_format is not mutated; no row of it runs writeNumber).
# Every `old` was counted EXACTLY once in its file at the gated candidate by a python3 -I script (no Julia ran). RE-FIT any `old` that `tools/warm.sh fmt` rewraps.
TW = "test/core_text/test_wr2_swipl.jl"
TWS = "test/core_text/test_write_swipl.jl"
TFW = "test/core_text/test_float_write_swipl.jl"
TWF = "test/core_text/test_write_family_swipl.jl"
TWC = "test/core_lang/test_write_cells.jl"
TCM = "test/core_lang/test_context_module_swipl.jl"
TMC = "test/core_lang/test_metacall.jl"
T_FMT = [TW]                                  # the format path of writeNumber, the CVT_* conversions
T_NUM = [TW, TWS, TFW, TWF, TWC]              # the default path of writeNumber
T_PORT = [TW, TWF, TWS, TWC, TCM, TMC]        # callPortray, the blobs(portray) branch of writeAtom
TARGETS = T_PORT + [TFW]                      # the baseline's targets (mutate_ci.py plan reads TARGETS): every file a mutant lists
W = "src/pl-write.jl"
X = "src/os/pl-text.jl"
# writeAtom's portray branch: the call and its result handling (unique by the callPortray line)
PB = "        rc = callPortray(av, 1200, options)\n        PL_close_foreign_frame(ld, fid)\n"
# _get_text_write's flag lists
CF = ("        PL_WRT_QUOTED | PL_WRT_QUOTE_NON_ASCII | PL_WRT_IGNOREOPS | PL_WRT_VARNAMES |\n"
      "        PL_WRT_NODOTINATOM | PL_WRT_BRACETERMS\n")
MUTANTS = [
    # ── writeNumber: the formats (pl-write.c:1832-1856) ──
    dict(id="WR2-N1 the integer_format test is flipped: the default goes through do_format, another format is written as digits (KILL TW:190, t0: `~D` of 1234567 is 1,234,567)",
         file=W, targets=T_FMT,
         old='        if options.integer_format != "~d"           # get_atom_text(integer_format, &fmt)\n',
         new='        if options.integer_format == "~d"           # get_atom_text(integer_format, &fmt)\n'),
    dict(id="WR2-N3 the float_format test is flipped (KILL TW:190, t16: `~2f` of 3.14159 is 3.14, the fast path writes 3.14159)",
         file=W, targets=T_FMT,
         old='    if options.float_format != "~h"                 # get_atom_text(float_format, &fmt)\n',
         new='    if options.float_format == "~h"                 # get_atom_text(float_format, &fmt)\n'),
    dict(id="WR2-N5 every integer goes through do_format, the fast path is skipped (EQUIVALENT: do_format's `~d` is the digits)",
         file=W, targets=T_NUM,
         equivalent="do_format's `~d` with no numeric argument prints the integer's decimal digits (src/os/pl-fmt.jl:554-555, arg 0 -> formatInteger(nothing, 0, 10, ...)), what the fast path prints (src/pl-write.jl:1009-1021); separate_number runs before either, with the same format text; the fast path is the kept DIVERGES in writeNumber's header",
         old='        if options.integer_format != "~d"           # get_atom_text(integer_format, &fmt)\n',
         new='        if true\n'),
    dict(id="WR2-N6 every float goes through do_format, the fast path is skipped (EQUIVALENT: do_format's `~h` is format_float(f, 3, 'e'))",
         file=W, targets=T_NUM,
         equivalent="do_format's `~h` with no numeric argument is `format_float(f.f, 3, 'e')` (src/os/pl-fmt.jl:1354-1356, 1389: arg defaults to 3 for `h`), what the fast path prints (src/pl-write.jl:1033-1035); separate_number runs before either, with the same format text",
         old='    if options.float_format != "~h"                 # get_atom_text(float_format, &fmt)\n',
         new='    if true\n'),
    dict(id="WR2-N7 a float is written with the integer_format text (KILL TW:190, t16: `~2f` is not the float's format; t21 too)",
         file=W, targets=T_FMT,
         old="        return _write_number_format(t0, t, options.float_format, options)\n",
         new="        return _write_number_format(t0, t, options.integer_format, options)\n"),
    dict(id="WR2-N9 separate_number is skipped on the format path (KILL TW:190, t29: `a=1` with `-~d` is `a= -1`, the space is separate_number's; t31, t34, t38 too)",
         file=W, targets=T_FMT,
         old="    separate_number(options.out, negative, fmt) || return false\n",
         new=""),
    dict(id="WR2-N10 an int64's sign is flipped for separate_number on the format path (KILL TW:190, t31: `a= -1` with `~D` needs the space of a negative number)",
         file=W, targets=T_FMT,
         old="        (integer_is_int64(t) ? int64_value(t) < 0 : bigint_value(t) < 0)\n",
         new="        (integer_is_int64(t) ? int64_value(t) > 0 : bigint_value(t) < 0)\n"),
    dict(id="WR2-N11 a bignum's sign is flipped for separate_number on the format path (KILL TW:190, t64: `a= -123456789012345678901234567890` with `~D` is `a= -123,456,...`, the space of a negative bignum is separate_number's)",
         file=W, targets=T_FMT,
         old="        (integer_is_int64(t) ? int64_value(t) < 0 : bigint_value(t) < 0)\n",
         new="        (integer_is_int64(t) ? int64_value(t) < 0 : bigint_value(t) > 0)\n"),
    dict(id="WR2-N12 a float's sign is ignored by separate_number on the format path (KILL TW:190, t35: `a= -1.5` with `~1f`)",
         file=W, targets=T_FMT,
         old="        signbit(float_value(t))\n",
         new="        false\n"),
    dict(id="WR2-N13 do_format is given no argument (KILL TW:190, t0: the one argument of `~D` is missing: format's `not enough arguments`)",
         file=W, targets=T_FMT,
         old="    return do_format(options.ld, options.out, txt, 1, t0, options.m.index)\n",
         new="    return do_format(options.ld, options.out, txt, 0, t0, options.m.index)\n"),
    dict(id="WR2-N14 the format text is read as ISO Latin-1 (KILL TW:190, t63: `float_format('\\U0001D431~w')` is the four UTF-8 bytes as four characters)",
         file=W, targets=T_FMT,
         old="    txt = PL_chars_t(Vector{UInt8}(codeunits(fmt)), length(fmt), ENC_UTF8, false)\n",
         new="    txt = PL_chars_t(Vector{UInt8}(codeunits(fmt)), length(fmt), ENC_ISO_LATIN_1, false)\n"),
    # ── writeNumber: the default path (the separating space) ──
    dict(id="WR2-N15 an int64 is never separated by the default path (KILL TWS:276: the corpus rows `a- -1`, `1 - -1`, text_corpora_testlib.jl:18-19, against swipl)",
         file=W, targets=T_NUM,
         old="            separate_number(options.out, v < 0, options.integer_format) || return false\n",
         new="            separate_number(options.out, false, options.integer_format) || return false\n"),
    dict(id="WR2-N16 a float is never separated by the default path (KILL TFW:208/212/219: `- -1.5`, `a- -2.5e-07`, `a- -0.0`)",
         file=W, targets=T_NUM,
         old="    separate_number(options.out, signbit(f), options.float_format) || return false\n",
         new="    separate_number(options.out, false, options.float_format) || return false\n"),
    dict(id="WR2-N17 a bignum is never separated by the default path (KILL TW:190, t65: `write(a- -123456789012345678901234567890)` is `a- -1234...`, the digits are written by PutString, so the space is separate_number's alone)",
         file=W, targets=T_NUM,
         old="            separate_number(options.out, z < 0, options.integer_format) || return false\n",
         new="            separate_number(options.out, false, options.integer_format) || return false\n"),
    # ── writeAtom: the blobs(portray) branch (pl-write.c:1273-1297) ──
    dict(id="WR2-P1 portray/1's success makes the write fail (KILL TW:190, t47: `f(<S>,a,[])` is a stream written by portray/1; t48, t49, t55, t56, t61, t62)",
         file=W, targets=T_PORT,
         old=PB + "        rc == 1 && return 1\n",
         new=PB + "        rc == 1 && return 0\n"),
    dict(id="WR2-P3 portray/1's error is taken for success (KILL TW:190, t58: portray/1 throws `portray_oops`, the row answers `ex(portray_oops)`)",
         file=W, targets=T_PORT,
         old=PB + "        rc == 1 && return 1\n        rc == 0 || return 0                         # error\n",
         new=PB + "        rc == 1 && return 1\n        rc == 0 || return 1                         # error\n"),
    dict(id="WR2-P4 portray/1's error is taken for a decline: the blob is written after it (KILL TW:190, t58: the ball is lost or the blob follows it)",
         file=W, targets=T_PORT,
         old=PB + "        rc == 1 && return 1\n        rc == 0 || return 0                         # error\n",
         new=PB + "        rc == 1 && return 1\n"),
    dict(id="WR2-P5 `[]` is offered to portray/1 (the `!is_nil(a)` test is dropped) (KILL TW:190, t50: `[]` with blobs(portray) and `portray(_) -> P` is `[]`)",
         file=W, targets=T_PORT,
         old="        options.gd.halt_cleaning <= CLN_PROLOG && !is_nil(a)\n",
         new="        options.gd.halt_cleaning <= CLN_PROLOG\n"),
    dict(id="WR2-P6 the blob test is `is_blob(a)` alone (EQUIVALENT: the one reserved symbol is `[]`, which `!is_nil` excludes)",
         file=W, targets=T_PORT,
         equivalent="the kernel's only reserved symbol is `[]` (src/pl-ressymbol.jl:12-17; dict, trienode, no_value, term_t_free are not ported) and `!is_nil(a)` (src/pl-write.jl:869) excludes it, so `is_blob(a)` selects the same atoms as `is_reserved_symbol(a) || is_blob(a)`",
         old="    if _ison(options, PL_WRT_BLOB_PORTRAY) && (is_reserved_symbol(a) || is_blob(a)) &&\n",
         new="    if _ison(options, PL_WRT_BLOB_PORTRAY) && is_blob(a) &&\n"),
    dict(id="WR2-P7 the blob test is `is_reserved_symbol(a)` alone: a stream is never offered (KILL TW:190, t47: the stream blob is written `<S>` by portray/1; t48, t49)",
         file=W, targets=T_PORT,
         old="    if _ison(options, PL_WRT_BLOB_PORTRAY) && (is_reserved_symbol(a) || is_blob(a)) &&\n",
         new="    if _ison(options, PL_WRT_BLOB_PORTRAY) && is_reserved_symbol(a) &&\n"),
    dict(id="WR2-P8 every atom is offered to portray/1, text atoms too (KILL TW:190, t49 and t52: `a`, `'A b'`, `abc` are written by the atom writer, not `P`)",
         file=W, targets=T_PORT,
         old="    if _ison(options, PL_WRT_BLOB_PORTRAY) && (is_reserved_symbol(a) || is_blob(a)) &&\n",
         new="    if _ison(options, PL_WRT_BLOB_PORTRAY) && true &&\n"),
    dict(id="WR2-P9 the blobs(portray) option is not read: a blob is always offered (KILL TW:190, t60: `write_term(f(S), [])` is `f(<stream>(0x...)` with portray/1 defined)",
         file=W, targets=T_PORT,
         old="    if _ison(options, PL_WRT_BLOB_PORTRAY) && (is_reserved_symbol(a)",
         new="    if (is_reserved_symbol(a)"),
    dict(id="WR2-P10 the atom is not put into the portray argument (KILL TW:190, t47: portray/1 gets a fresh variable, `is_stream(_)` fails, the blob is written `<stream>(0x...)`)",
         file=W, targets=T_PORT,
         old="        PL_put_atom(ld, av, a)\n" + PB,
         new="        nothing\n" + PB),
    dict(id="WR2-P11 writeAtom's own halt test is dropped (EQUIVALENT: callPortray tests halt_cleaning itself)",
         file=W, targets=T_PORT,
         equivalent="callPortray repeats the test as its first statement (src/pl-write.jl:1318, `gd.halt_cleaning > CLN_PROLOG && return 0`): the answer is 0 and the blob is written by the fall-through at pl-write.jl:880, whether writeAtom tested before it or not; only a foreign frame and a term reference are opened for nothing",
         old="        options.gd.halt_cleaning <= CLN_PROLOG && !is_nil(a)\n",
         new="        !is_nil(a)\n"),
    dict(id="WR2-P12 writeAtom's halt test is `<`: no portray call during CLN_PROLOG (KILL TW:223, the halt testset at TW:216: t48 under gd.halt_cleaning = CLN_PROLOG is `<S>`, portray/1 IS called for the stream blob; the mutant writes `<stream>(0x...)`)",
         file=W, targets=T_PORT,
         old="        options.gd.halt_cleaning <= CLN_PROLOG && !is_nil(a)\n",
         new="        options.gd.halt_cleaning < CLN_PROLOG && !is_nil(a)\n"),
    dict(id="WR2-P14 the priority writeAtom hands callPortray is 999, not 1200 (KILL TW:190, t66: portray_goal `wr2_pg2(T, O) :- is_stream(T), write(O)` with blobs(portray) writes its options: `priority(1200)`, the mutant `priority(999)`; the option's own priority(999) is not it)",
         file=W, targets=T_PORT,
         old="        rc = callPortray(av, 1200, options)\n",
         new="        rc = callPortray(av, 999, options)\n"),
    # ── callPortray: the halt test (pl-write.c:1213, `GD->halt.cleaning > CLN_PROLOG`) ──
    dict(id="WR2-C1 callPortray does not test halt_cleaning (KILL TW:228, the halt testset at TW:216: t67 `write_term(f(foo), [portray(true)])` under CLN_FOREIGN/CLN_IO/CLN_DATA is `f(foo)`, the mutant calls portray(foo) and writes `f(bar)`; a LITERAL row, no oracle)",
         file=W, targets=T_PORT,
         old="    gd.halt_cleaning > CLN_PROLOG && return 0        # avoid dangerous callbacks\n",
         new=""),
    dict(id="WR2-C2 callPortray refuses from CLN_PROLOG on, not after it (KILL TW:223, the halt testset at TW:216: t67 under CLN_PROLOG is `f(bar)`, portray/1 is still called; the mutant writes `f(foo)`)",
         file=W, targets=T_PORT,
         old="    gd.halt_cleaning > CLN_PROLOG && return 0        # avoid dangerous callbacks\n",
         new="    gd.halt_cleaning >= CLN_PROLOG && return 0        # avoid dangerous callbacks\n"),
    # ── _get_text_write: the write options of each CVT_* flag (pl-text.c:372-379) ──
    dict(id="WR2-T1 CVT_WRITEQ is written without PL_WRT_QUOTED (KILL TW:370, r5: `'a b'` quoted is [39,97,32,98,39])",
         file=X, targets=[TW],
         old="        PL_WRT_QUOTED | PL_WRT_NUMBERVARS\n    elseif (flags & CVT_WRITE_CANONICAL)",
         new="        PL_WRT_NUMBERVARS\n    elseif (flags & CVT_WRITE_CANONICAL)"),
    dict(id="WR2-T2 CVT_WRITEQ is written without PL_WRT_NUMBERVARS (KILL TW:370, r17: `'$VAR'(3)` under writeq is `D`)",
         file=X, targets=[TW],
         old="        PL_WRT_QUOTED | PL_WRT_NUMBERVARS\n    elseif (flags & CVT_WRITE_CANONICAL)",
         new="        PL_WRT_QUOTED\n    elseif (flags & CVT_WRITE_CANONICAL)"),
    dict(id="WR2-T3 CVT_WRITE is written without PL_WRT_NUMBERVARS (KILL TW:370, r16: `'$VAR'(3)` under write is `D`; r7 `f(A,_,A)` too)",
         file=X, targets=[TW],
         old="        PL_WRT_NUMBERVARS\n    end\n\n    result = nothing",
         new="        0\n    end\n\n    result = nothing"),
    dict(id="WR2-T4 CVT_WRITE_CANONICAL is written without PL_WRT_IGNOREOPS (KILL TW:370, r33: `1 - 2` canonical is `-(1,2)`)",
         file=X, targets=[TW],
         old=CF, new=CF.replace(" | PL_WRT_IGNOREOPS", "")),
    dict(id="WR2-T5 CVT_WRITE_CANONICAL is written without PL_WRT_BRACETERMS (KILL TW:370, r45: `{a,b}` canonical is `{}(','(a,b))`, pl-write.c:2430)",
         file=X, targets=[TW],
         old=CF, new=CF.replace(" | PL_WRT_BRACETERMS", "")),
    dict(id="WR2-T6 CVT_WRITE_CANONICAL is written without PL_WRT_NODOTINATOM (EQUIVALENT: no reader of the flag in src/)",
         file=X, targets=[TW],
         equivalent="no code of src/ reads PL_WRT_NODOTINATOM: the constant (src/SWI-Prolog.jl:239) and the two places that set it (src/pl-write.jl:2471, src/os/pl-text.jl:70); the `dot_in_atom` test of pl-write.c:514, 598 is not ported",
         old=CF, new=CF.replace("PL_WRT_NODOTINATOM | ", "")),
    dict(id="WR2-T7 CVT_WRITE_CANONICAL is written without PL_WRT_VARNAMES (KILL TW:370, r9: `f(X,Y,X)` canonical is `f(A,_,A)`, the numbered variables are names)",
         file=X, targets=[TW],
         old=CF, new=CF.replace(" | PL_WRT_VARNAMES", "")),
    dict(id="WR2-T8 CVT_WRITE_CANONICAL is written without PL_WRT_QUOTED (KILL TW:370, r6: `'a b'` canonical is [39,97,32,98,39])",
         file=X, targets=[TW],
         old=CF, new=CF.replace("PL_WRT_QUOTED | ", "")),
    dict(id="WR2-T9 CVT_WRITE_CANONICAL is written without PL_WRT_QUOTE_NON_ASCII (KILL TW:406, a literal row, no oracle: the canonical text of `'é'(λ)` is `'é'('λ')`; the canonical oracle rows are ASCII)",
         file=X, targets=[TW],
         old=CF, new=CF.replace(" | PL_WRT_QUOTE_NON_ASCII", "")),
    # ── _get_text_write: the numbering (pl-text.c:382-389) and the text ──
    dict(id="WR2-T10 the numbering is not told to name singletons `_` (KILL TW:370, r7: `f(X,Y,X)` under write is `f(A,_,A)`; TW:397)",
         file=X, targets=[TW],
         old="is_acyclic_cells(ld, -(l + 1)) ? 1 : 0,",
         new="0,"),
    dict(id="WR2-T11 an NV_ERROR of the numbering is ignored (EQUIVALENT: no error is reachable with numbered_check false and AV_SKIP)",
         file=X, targets=[TW],
         equivalent="numberVars returns NV_ERROR for a number out of the tagged range (src/pl-prims.jl:523-526: the offset is 0 here, or past 2^60 variables), an attributed variable under AV_ERROR (:549-553, here AV_SKIP, pl-text.jl:80) and an already numbered term (:554-558: `numbered_check` is false, pl-text.jl:82), so the test at pl-text.jl:84 is always true",
         old="        if numberVars(ld, l, options, 0) != NV_ERROR\n",
         new="        if numberVars(ld, l, options, 0) != NV_ERROR || true\n"),
    dict(id="WR2-T12 the numbervars frame is never ended (KILL TW:399: the term's first argument is a variable again after the call; r7's term keeps `'$VAR'(0)`)",
         file=X, targets=[TW],
         old="        END_NUMBERVARS(ld, true, savedf)\n",
         new="        nothing\n"),
    dict(id="WR2-T13 the EOS is not written (KILL TW:411, a literal row: the text of the string \"a\\0\" under CVT_WRITE is [97,0]; without the EOS the strip at pl-text.jl:97 removes the text's own NUL; the CVT equivalent swipl computes agrees)",
         file=X, targets=[TW],
         old="                Sputcode(0, fd) >= 0 &&                  # Sputcode(EOS, fd)\n",
         new=""),
    dict(id="WR2-T14 the stream is not flushed before the buffer is read (KILL TW:370, r1: the buffer of the \"w\" memory stream is empty, the text is [] not `foo`; every row)",
         file=X, targets=[TW],
         old="                Sflush(fd) >= 0\n",
         new="                true\n"),
    dict(id="WR2-T15 the EOS stays in the text (KILL TW:370, r1: every text ends in a 0, [102,111,111,0]; TW:391)",
         file=X, targets=[TW],
         old="                    n > 0 && b[n] == 0x00 && (n -= 1)    # text->length = size-1\n",
         new=""),
    dict(id="WR2-T16 the memory stream's encoding is not set to UTF-8 (EQUIVALENT: a text stream is UTF-8 already)",
         file=X, targets=[TW],
         equivalent="Sopenmem makes a SIO_TEXT stream (src/os/pl-stream.jl:1300) and Snew gives a SIO_TEXT stream ENC_UTF8 (pl-stream.jl:1094), so the assignment at pl-text.jl:89 changes nothing",
         old="            fd.encoding = ENC_UTF8\n",
         new=""),
    dict(id="WR2-T17 the text's length is its bytes, not its code points (KILL TW:391: `'日本語'(λ)` under CVT_WRITEQ has fewer code points than bytes)",
         file=X, targets=[TW],
         old="length(String(copy(bytes)))",
         new="length(bytes)"),
    dict(id="WR2-T18 the text is tagged ISO Latin-1 (KILL TW:392: the encoding of the result is ENC_UTF8, the approved DIVERGES)",
         file=X, targets=[TW],
         old="PL_chars_t(bytes, length(String(copy(bytes))), ENC_UTF8, false)",
         new="PL_chars_t(bytes, length(String(copy(bytes))), ENC_ISO_LATIN_1, false)"),
    dict(id="WR2-T19 the text is tagged canonical (KILL TW:393: `@test !r[4]`, the result's `canonical` field is false: UTF-8 text is never canonical, pl-text.jl:29)",
         file=X, targets=[TW],
         old="PL_chars_t(bytes, length(String(copy(bytes))), ENC_UTF8, false)",
         new="PL_chars_t(bytes, length(String(copy(bytes))), ENC_UTF8, true)"),
    dict(id="WR2-T20 the term is written at priority 999, not 1200 (KILL TW:370, r58: `(a,b)` under write is `a,b`; r100 `p:-q,r`)",
         file=X, targets=[TW],
         old="PL_write_term(gd, ld, fd, l, 1200, wflags)",
         new="PL_write_term(gd, ld, fd, l, 999, wflags)"),
    dict(id="WR2-T21 PL_get_text takes the write result for a failure (KILL TW:370, r1: every CVT_WRITE* row is NOTEXT)",
         file=X, targets=[TW],
         old="        r = _get_text_write(ld, l, flags)\n        r !== nothing && return r\n",
         new="        r = _get_text_write(ld, l, flags)\n"),
]
