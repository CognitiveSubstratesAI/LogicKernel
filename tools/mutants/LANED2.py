# ORIGINAL: lane D's mutant list (piece 2) — no swipl-devel counterpart.
# tools/mutants/LANED2.py — the mutation battery of lane D piece 2 (os/pl-file.c Edinburgh I/O: see/1, seen/0, seeing/1, tell/1,
# append/1, telling/1, told/0, do_tell, findStreamFromFile, the IO_SEE/IO_TELL stream-context flags), run ONCE, in CI
# (.github/workflows/mutation.yml). Format: as LANED1.py. Killed by test/core_lang/test_lane_d_swipl.jl rows d070-d097; pl_see is also
# reached by the loader (compileFile), so the targets add the boot-image and open/close files. UNTESTED: nothing was compiled.
# Every `old` was checked to occur exactly once in src/os/pl-file.jl at wip/lane-d (a text count, no Julia).
# NOT LISTED (equivalent, read not run): `freeStream`'s `delete!(gd.stream_context_flags, s.context)`: a closed stream's table entry is
# `nothing` and `findStreamFromFile` skips it, and a new stream gets a new context number, so a stale flag is never read.
TL = ["test/core_lang/test_lane_d_swipl.jl"]
TS = ["test/core_lang/test_lane_d_swipl.jl", "test/files/test_open_close_swipl.jl", "test/db/test_boot_image_swipl.jl"]
TARGETS = TS
F = "src/os/pl-file.jl"
MUTANTS = [
    dict(id="LD2-1 findStreamFromFile ignores the context flag: a stream opened by open/3 is found (KILL: d097)", file=F, targets=TS,
         old="           (get(gd.stream_context_flags, s.context, 0) & flags) != 0\n",
         new="           true\n"),
    dict(id="LD2-2 findStreamFromFile compares no file name: the first flagged stream is found (KILL: d075 with a second file)", file=F, targets=TL,
         old="        if fn !== nothing && sym_key(fn) == sym_key(name) &&\n",
         new="        if fn !== nothing &&\n"),
    dict(id="LD2-3 see/1 does not look for an open stream of the file: it opens it again (KILL: d075)", file=F, targets=TL,
         old="    s = findStreamFromFile(gd, a, IO_SEE)\n",
         new="    s = nothing\n"),
    dict(id="LD2-4 see/1 does not mark the stream IO_SEE (KILL: d075)", file=F, targets=TL,
         old="    setStreamContextFlag(gd, s, IO_SEE)             # set(getStreamContext(s), IO_SEE)\n",
         new="    getStreamContext(gd, s)\n"),
    dict(id="LD2-5 see/1 does not push the input context: seen leaves the file's stream as the current input (KILL: d072)", file=F, targets=TL,
         old="    push_input_context(ld, mk_sym(T, :see))         # push_input_context(ATOM_see)\n",
         new="    nothing\n"),
    dict(id="LD2-6 see(user) selects nothing (KILL: d074)", file=F, targets=TL,
         old="        ld.IO_streams[SNO_CURRENT_INPUT + 1] = Suser_input(ld)   # Scurin = Suser_input\n",
         new="        nothing\n"),
    dict(id="LD2-7 seeing/1 answers the stream even for user (KILL: d073, d074)", file=F, targets=TL,
         old="    if Scurin(ld) === Suser_input(ld)\n        return PL_unify_atom(ld, PL__t0, mk_sym(T, :user)) ? FTRUE : FFALSE\n",
         new="    if false\n        return PL_unify_atom(ld, PL__t0, mk_sym(T, :user)) ? FTRUE : FFALSE\n"),
    dict(id="LD2-8 tell/1 opens for append (KILL: d082, d096)", file=F, targets=TL,
         old="    return do_tell(ld, PL__t0, mk_sym(T, :write)) ? FTRUE : FFALSE\n",
         new="    return do_tell(ld, PL__t0, mk_sym(T, :append)) ? FTRUE : FFALSE\n"),
    dict(id="LD2-9 append/1 opens for writing (KILL: d086)", file=F, targets=TL,
         old="    return do_tell(ld, PL__t0, mk_sym(T, :append)) ? FTRUE : FFALSE\nend\n\n# PORT: pl-file.c telling",
         new="    return do_tell(ld, PL__t0, mk_sym(T, :write)) ? FTRUE : FFALSE\nend\n\n# PORT: pl-file.c telling"),
    dict(id="LD2-10 do_tell does not look for an open stream of the file (KILL: d087)", file=F, targets=TL,
         old="    s = findStreamFromFile(gd, a, IO_TELL)\n",
         new="    s = nothing\n"),
    dict(id="LD2-11 do_tell does not push the output context: told closes the user output's successor wrongly (KILL: d088)", file=F, targets=TL,
         old="    pushOutputContext(ld, s)\n    return true\nend\n\n# PORT: pl-file.c tell as pl_tell1_va",
         new="    setStandardStream(ld, SNO_CURRENT_OUTPUT, s)\n    return true\nend\n\n# PORT: pl-file.c tell as pl_tell1_va"),
    dict(id="LD2-12 tell(user) selects nothing (KILL: d085)", file=F, targets=TL,
         old="        setStandardStream(ld, SNO_CURRENT_OUTPUT, Suser_output(ld)::IOSTREAM)\n",
         new="        nothing\n"),
    dict(id="LD2-13 telling/1 answers the stream for user (KILL: d084, d085)", file=F, targets=TL,
         old="    if Scurout(ld) === Suser_output(ld)\n",
         new="    if false\n"),
    dict(id="LD2-14 told does not close the stream (KILL: d086, d087: the second open of the file finds it unflushed or open)", file=F, targets=TL,
         old="    s !== nothing && return closeStream(ld, s) ? FTRUE : FFALSE\n\n    return symbol_no_stream(ld, mk_sym(T, :current_output)) ? FTRUE : FFALSE\n",
         new="    s !== nothing && return FTRUE\n\n    return symbol_no_stream(ld, mk_sym(T, :current_output)) ? FTRUE : FFALSE\n"),
]
