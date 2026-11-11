# ORIGINAL: lane D's mutant list (piece 6) — no swipl-devel counterpart.
# tools/mutants/LANED6.py — the mutation battery of lane D piece 6 (relay 5): '$size_stream'/2, fill_buffer/1 and the Ssize
# rewrite (pl-file.c, pl-stream.c), then the groups after them. Format: as LANED1.py. Killed by test/core_lang/test_lane_d_swipl.jl
# (rows d185 on). UNTESTED: nothing was compiled. Every `old` was checked to occur exactly once in its file at wip/lane-d.
# TARGETS: the only test files that reach Ssize / the buffer predicates are test_lane_d_swipl.jl (the rows) and every test that opens
# a file in append/update mode with a BOM check (none found: grep of test/ for `append`).
TL = ["test/core_lang/test_lane_d_swipl.jl"]
TARGETS = TL
F = "src/os/pl-file.jl"
G = "src/os/pl-stream.jl"
MUTANTS = [
    dict(id="LD6-1 Ssize: a file's size is one more (KILL: d185, d187, d195)", file=G, targets=TL,
         old="        io isa IOStream && return Int64(filesize(io))\n",
         new="        io isa IOStream && return Int64(filesize(io)) + 1\n"),
    dict(id="LD6-2 Ssize: the seek-to-end measure is skipped, so no size (KILL: d189)", file=G, targets=TL,
         old="    if S_has_seek(s)\n        here = Stell64(s)\n",
         new="    if false && S_has_seek(s)\n        here = Stell64(s)\n"),
    dict(id="LD6-3 Ssize: the position is not restored (KILL: d210, d211)", file=G, targets=TL,
         old="        Sseek64(s, here, SIO_SEEK_SET)\n\n        return enddata\n",
         new="        return enddata\n"),
    dict(id="LD6-4 Ssize: a failed seek to the end still gives its position (KILL: d188)", file=G, targets=TL,
         old="            enddata = Int64(-1)\n",
         new="            enddata = Stell64(s)\n"),
    dict(id="LD6-5 Ssize: no ESPIPE error for a stream without a seek (no row reaches it: a pipe from item 3)", file=G, targets=TL, eq=True,
         equivalent="no row reaches a stream without a seek function yet (pipe rows of item 3)",
         old="    s.io_errno = ESPIPE\n    S__seterror(s)\n    return Int64(-1)\nend\n",
         new="    return Int64(-1)\nend\n"),
    dict(id="LD6-6 '$size_stream': a size of 0 is refused (KILL: d186, d189)", file=F, targets=TL,
         old="    sz >= 0 && return PL_unify_int64(ld, A2, Int(sz)) ? FTRUE : FFALSE\n",
         new="    sz > 0 && return PL_unify_int64(ld, A2, Int(sz)) ? FTRUE : FFALSE\n"),
    dict(id="LD6-7 '$size_stream': the stream's error is not reported (KILL: d188)", file=F, targets=TL,
         old="    streamStatus(ld, s) || return FFALSE                        # PL_release_stream(s)\n\n    sz >= 0",
         new="    sz >= 0"),
    dict(id="LD6-8 '$size_stream': the permission error says write (KILL: none: every non-sized stream raises io_error first? see handoff)",
         file=F, targets=TL, eq=True,
         equivalent="the permission_error(reposition, stream, S) branch is reached only for a size < 0 without a stream error: Ssize sets one for every -1 (ESPIPE, or the failed seek), so the branch looks unreachable from the predicate; upstream has it as the same guard",
         old="    _PL_permission_error(ld, :reposition, :stream, A1)\n    return FFALSE\nend\n\n",
         new="    _PL_permission_error(ld, :write, :stream, A1)\n    return FFALSE\nend\n\n"),
    dict(id="LD6-9 '$size_stream': the second argument is not unified (KILL: d190)", file=F, targets=TL,
         old="Int(sz)) ? FTRUE : FFALSE\n\n    _PL_permission_error",
         new="Int(sz) + 1) ? FTRUE : FFALSE\n\n    _PL_permission_error"),
    dict(id="LD6-10 fill_buffer: the buffer's first byte is consumed (KILL: d196, d199, d200)", file=F, targets=TL,
         old="            s.bufp -= 1\n",
         new=""),
    dict(id="LD6-11 fill_buffer: an unbuffered stream is accepted (KILL: d202)", file=F, targets=TL,
         old="        if (s.flags & SIO_NBUF) != 0\n            _PL_permission_error(ld, :fill_buffer",
         new="        if false\n            _PL_permission_error(ld, :fill_buffer"),
    dict(id="LD6-12 fill_buffer: a stream at end of file is filled again (KILL: d198)", file=F, targets=TL,
         old="        if (s.flags & SIO_FEOF) == 0\n            if S__fillbuf(s) < 0",
         new="        if true\n            if S__fillbuf(s) < 0"),
    dict(id="LD6-13 the registration of fill_buffer/1 is gone (KILL: d196-d209)", file=F, targets=TL,
         old='    PL_extension("fill_buffer", 1, pl_fill_buffer1_va, PL_FA_VARARGS),\n',
         new=""),
    dict(id="LD6-14 the registration of '$size_stream'/2 is gone (KILL: d185-d195)", file=F, targets=TL,
         old='    PL_extension("\\$size_stream", 2, pl_dsize_stream2_va, PL_FA_VARARGS),\n',
         new=""),
]
