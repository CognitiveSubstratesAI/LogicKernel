# ORIGINAL: Edinburgh I/O's mutant list (EDIO1) — no swipl-devel counterpart.
# tools/mutants/EDIO1.py — the mutation battery of the Edinburgh I/O group (os/pl-file.c: see/1, seen/0, seeing/1, tell/1, append/1,
# telling/1, told/0, do_tell, findStreamFromFile and the IO_SEE / IO_TELL stream-context flags), run ONCE, in CI (.github/workflows/mutation.yml;
# locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as LANED2.py): `id`, `file`, `old` (must occur EXACTLY once), `new` (!= old),
# optional `equivalent` (the reason, file:line), `targets`.
# Killed by test/core_lang/test_edinburgh_io_swipl.jl (rows e001-e061) and test/core_lang/test_lane_d_swipl.jl (d070-d097; its own list is LANED2.py:
# the ids here name the rows that kill the mutant FIRST). pl_see is also called by the loader (compileFile: src/pl-qlf.jl), so the targets add
# every test file that loads a file or reads the boot image (D-0238: a list names
# EVERY test file that exercises the mutated code). Verdicts: written by the battery, not yet run. UNTESTED: nothing was compiled.
# Every `old` was counted exactly once in src/os/pl-file.jl at wip/edinburgh-io by `python3 -I tools/mutants/EDIO1.py --check` (a text count, no Julia);
# RE-FIT any that fmt rewraps.
# RECORDED EQUIVALENT: none in the list. (EDIO1-12 was declared equivalent on the reading that no output stream carries SIO_NOFEOF; row e061 refutes it:
# set_stream/2 on an ALIAS reaches set_stream() with no SS_READ test, so an output stream can carry it, and told then keeps it open.)
# NOT LISTED (equivalent, read not run): `setStreamContextFlag`'s `| flag` -> `= flag`: a stream is flagged once, at its opening by see/1 or by
# tell/1, never both, so there is no earlier flag to keep (src/os/pl-file.jl pl_see / do_tell: the only two callers). `freeStream`'s
# `delete!(gd.stream_context_flags, ...)`: a closed stream's table entry is `nothing`, findStreamFromFile skips it, and a new stream gets a new context
# number (LANED2.py has the same note). `pl_see`/`do_tell`'s SH_ALIAS|SH_UNLOCKED flags: get_stream_handle reads SH_ALIAS only in the error text
# (not_a_stream), and these calls carry no SH_ERRORS.
NEW = "test/core_lang/test_edinburgh_io_swipl.jl"
LD = "test/core_lang/test_lane_d_swipl.jl"
TS = [
    NEW, LD, "test/core_lang/test_s2a_swipl.jl", "test/core_lang/test_with_output_to_swipl.jl", "test/files/test_open_close_swipl.jl",
    "test/files/test_load_swipl.jl", "test/files/test_qlf_swipl.jl", "test/db/test_boot_image_swipl.jl",
]
TL = [NEW, LD]
TARGETS = TS
F = "src/os/pl-file.jl"
MUTANTS = [
    dict(id="EDIO1-1 findStreamFromFile never finds a stream (KILL: e014, e005, e051)", file=F, targets=TL,
         old="           (get(gd.stream_context_flags, s.context, 0) & flags) != 0\n            return s\n",
         new="           (get(gd.stream_context_flags, s.context, 0) & flags) != 0\n            return nothing\n"),
    dict(id="EDIO1-2 IO_SEE is IO_TELL's bit: see(F) finds the stream tell(F) opened (KILL: e037)", file=F, targets=TL,
         old="const IO_SEE = 2\n",
         new="const IO_SEE = 1\n"),
    dict(id="EDIO1-3 IO_TELL is IO_SEE's bit: tell(F) finds the stream see(F) opened (KILL: e060)", file=F, targets=TL,
         old="const IO_TELL = 1\n",
         new="const IO_TELL = 2\n"),
    dict(id="EDIO1-4 tell/1 marks its stream IO_SEE: a second tell(F) does not find it (KILL: e051)", file=F, targets=TL,
         old="    setStreamContextFlag(gd, s, IO_TELL)            # set(getStreamContext(s), IO_TELL)\n",
         new="    setStreamContextFlag(gd, s, IO_SEE)             # set(getStreamContext(s), IO_TELL)\n"),
    dict(id="EDIO1-5 see/1 marks its stream IO_TELL: a second see(F) does not find it (KILL: e014, e005)", file=F, targets=TL,
         old="    setStreamContextFlag(gd, s, IO_SEE)             # set(getStreamContext(s), IO_SEE)\n",
         new="    setStreamContextFlag(gd, s, IO_TELL)            # set(getStreamContext(s), IO_SEE)\n"),
    dict(id="EDIO1-6 seen/0 leaves the input context alone: the stream below the see/1 is not current again (KILL: e003, e014)", file=F, targets=TS,
         old="    pop_input_context(ld)\n\n    s !== nothing && (s.flags & SIO_NOFEOF) != 0 && return true\n",
         new="    s !== nothing && (s.flags & SIO_NOFEOF) != 0 && return true\n"),
    dict(id="EDIO1-7 seen/0 closes a stream that ignores end of file (KILL: e058)", file=F, targets=TL,
         old="    pop_input_context(ld)\n\n    s !== nothing && (s.flags & SIO_NOFEOF) != 0 && return true\n",
         new="    pop_input_context(ld)\n\n"),
    dict(id="EDIO1-8 see/1's lookup by file name: the found stream is not made current (KILL: e005)", file=F, targets=TL,
         old="    s = findStreamFromFile(gd, a, IO_SEE)\n    if s !== nothing\n        ld.IO_streams[SNO_CURRENT_INPUT + 1] = s    # Scurin = s\n        return true\n",
         new="    s = findStreamFromFile(gd, a, IO_SEE)\n    if s !== nothing\n        return true\n"),
    dict(id="EDIO1-9 tell/1's lookup by file name: the found stream is not made current (KILL: e048)", file=F, targets=TL,
         old="    s = findStreamFromFile(gd, a, IO_TELL)\n    if s !== nothing\n        setStandardStream(ld, SNO_CURRENT_OUTPUT, s)\n        return true\n",
         new="    s = findStreamFromFile(gd, a, IO_TELL)\n    if s !== nothing\n        return true\n"),
    dict(id="EDIO1-10 see/1's open failure is not returned: the nothing reaches setStreamContextFlag (KILL: e018)", file=F, targets=TL,
         old="    s = openStream(ld, f, mode, 0)\n    s === nothing && return false\n\n    setStreamContextFlag(gd, s, IO_SEE)",
         new="    s = openStream(ld, f, mode, 0)\n\n    setStreamContextFlag(gd, s, IO_SEE)"),
    dict(id="EDIO1-11 tell/1's open failure is not returned: the nothing reaches setStreamContextFlag (KILL: e043, e044)", file=F, targets=TL,
         old="    s = openStream(ld, f, mode, 0)\n    s === nothing && return false\n\n    setStreamContextFlag(gd, s, IO_TELL)",
         new="    s = openStream(ld, f, mode, 0)\n\n    setStreamContextFlag(gd, s, IO_TELL)"),
    dict(id="EDIO1-12 told/0 closes a stream that ignores end of file: the SIO_NOFEOF early return is dropped (KILL: e061)", file=F, targets=TL,
         old="    popOutputContext(ld)\n\n    s !== nothing && (s.flags & SIO_NOFEOF) != 0 && return FTRUE\n",
         new="    popOutputContext(ld)\n\n"),
    dict(id="EDIO1-13 see/1's argument error is not returned: the nothing reaches get_stream_handle (KILL: e012, e013)", file=F, targets=TL,
         old="    a = PL_get_atom_ex(ld, f)\n    a === nothing && return false\n\n    s = get_stream_handle(ld, a, SH_ALIAS | SH_UNLOCKED)\n",
         new="    a = PL_get_atom_ex(ld, f)\n\n    s = get_stream_handle(ld, a, SH_ALIAS | SH_UNLOCKED)\n"),
    dict(id="EDIO1-14 tell/1's argument error is not returned (KILL: e040, e041, e042, e052)", file=F, targets=TL,
         old="    a = PL_get_atom_ex(ld, f)\n    a === nothing && return false\n\n    s = get_stream_handle(ld, a, SH_UNLOCKED)\n",
         new="    a = PL_get_atom_ex(ld, f)\n\n    s = get_stream_handle(ld, a, SH_UNLOCKED)\n"),
    dict(id="EDIO1-15 see/1 does not resolve an alias or a stream blob (KILL: e010, e011, e007)", file=F, targets=TL,
         old="    s = get_stream_handle(ld, a, SH_ALIAS | SH_UNLOCKED)\n    if s !== nothing\n        ld.IO_streams[SNO_CURRENT_INPUT + 1] = s    # Scurin = s\n",
         new="    s = nothing\n    if s !== nothing\n        ld.IO_streams[SNO_CURRENT_INPUT + 1] = s    # Scurin = s\n"),
    dict(id="EDIO1-16 seen/0 does not close: the file's stream stays open and the next see(F) continues in it (KILL: e001)", file=F, targets=TL,
         old="    s !== nothing && return closeStream(ld, s)\n\n    return symbol_no_stream(ld, mk_sym(T, :current_input))\n",
         new="    s !== nothing && return true\n\n    return symbol_no_stream(ld, mk_sym(T, :current_input))\n"),
    dict(id="EDIO1-17 told/0 pops no output context: the stream below the tell/1 is not current again (KILL: e030, e046)", file=F, targets=TS,
         old="    popOutputContext(ld)\n\n    s !== nothing && (s.flags & SIO_NOFEOF) != 0 && return FTRUE\n",
         new="    s !== nothing && (s.flags & SIO_NOFEOF) != 0 && return FTRUE\n"),
    dict(id="EDIO1-18 told/0 with nothing to close raises existence_error(stream, current_output) (KILL: e032, e033)", file=F, targets=TL,
         old="    s !== nothing && return closeStream(ld, s) ? FTRUE : FFALSE\n\n    return symbol_no_stream(ld, mk_sym(T, :current_output)) ? FTRUE : FFALSE\n",
         new="    return symbol_no_stream(ld, mk_sym(T, :current_output)) ? FTRUE : FFALSE\n"),
    dict(id="EDIO1-19 set_stream/2 applies eof_action(reset) to an output stream too: told no longer closes it (KILL: e059)", file=F,
         targets=[NEW, LD, "test/core_lang/test_s2a_swipl.jl"],
         old="    (:eof_action, SS_READ),\n",
         new="    (:eof_action, SS_BOTH),\n"),
]
if __name__ == "__main__":
    import sys
    if "--check" in sys.argv:
        src = open(F).read()
        bad = 0
        for m in MUTANTS:
            n = src.count(m["old"])
            ok = n == 1 and m["new"] != m["old"] and (m.get("equivalent") is None or len(m["equivalent"]) > 10)
            bad += not ok
            print(("ok  " if ok else "BAD ") + m["id"][:60] + ("" if n == 1 else "  count=%d" % n))
        print("%d mutants, %d bad" % (len(MUTANTS), bad))
        sys.exit(1 if bad else 0)
