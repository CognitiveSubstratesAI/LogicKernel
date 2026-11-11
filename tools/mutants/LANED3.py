# ORIGINAL: lane D's mutant list (piece 3) — no swipl-devel counterpart.
# tools/mutants/LANED3.py — the mutation battery of lane D piece 3 (pl-file.c NULL-STREAM: open_null_stream/1, Swrite_null, Sread_null,
# Sclose_null; the Snullfunctions dispatch in src/os/pl-stream.jl). Format: as LANED1.py. Killed by test/core_lang/test_lane_d_swipl.jl
# rows d098-d108; the dispatch mutants also by the stream files that reach S_write/S_close. UNTESTED: nothing was compiled.
# Every `old` was checked to occur exactly once in its file at wip/lane-d (a text count, no Julia).
# NOT LISTED: Sseek_null (no seek dispatch exists until S2b: nothing calls it).
TL = ["test/core_lang/test_lane_d_swipl.jl"]
TS = ["test/core_lang/test_lane_d_swipl.jl", "test/files/test_stream_swipl.jl", "test/files/test_open_close_swipl.jl"]
TARGETS = TS
F = "src/os/pl-file.jl"
S = "src/os/pl-stream.jl"
MUTANTS = [
    dict(id="LD3-1 a null stream accepts no byte: Swrite_null answers 0 (KILL: d098, d099)", file=F, targets=TL,
         old="Swrite_null(mem::Vector{UInt8}, from::Int, size::Int)::Int = size\n",
         new="Swrite_null(mem::Vector{UInt8}, from::Int, size::Int)::Int = 0\n"),
    dict(id="LD3-2 a null stream records no position (KILL: d098, d099, d103)", file=F, targets=TL,
         old="    sflags = SIO_NBUF | SIO_RECORDPOS | SIO_OUTPUT | SIO_TEXT\n",
         new="    sflags = SIO_NBUF | SIO_OUTPUT | SIO_TEXT\n"),
    dict(id="LD3-3 a null stream is binary (KILL: d102, d108)", file=F, targets=TL,
         old="    sflags = SIO_NBUF | SIO_RECORDPOS | SIO_OUTPUT | SIO_TEXT\n    s = Snew",
         new="    sflags = SIO_NBUF | SIO_RECORDPOS | SIO_OUTPUT\n    s = Snew"),
    dict(id="LD3-4 a null stream is an input stream (KILL: d101, d104)", file=F, targets=TL,
         old="    sflags = SIO_NBUF | SIO_RECORDPOS | SIO_OUTPUT | SIO_TEXT\n    s = Snew",
         new="    sflags = SIO_NBUF | SIO_RECORDPOS | SIO_INPUT | SIO_TEXT\n    s = Snew"),
    dict(id="LD3-5 a null stream is fully buffered (KILL: d105)", file=F, targets=TL,
         old="    sflags = SIO_NBUF | SIO_RECORDPOS | SIO_OUTPUT | SIO_TEXT\n    s = Snew",
         new="    sflags = SIO_FBUF | SIO_RECORDPOS | SIO_OUTPUT | SIO_TEXT\n    s = Snew"),
    dict(id="LD3-6 the encoding is set to octets after Snew (KILL: d102, d103)", file=F, targets=TL,
         old="    s.encoding = ENC_UTF8\n    return PL_unify_stream_or_alias(ld, PL__t0, s)",
         new="    s.encoding = ENC_OCTET\n    return PL_unify_stream_or_alias(ld, PL__t0, s)"),
    dict(id="LD3-7 the write dispatch has no null branch: the bytes go to the string writer (KILL: d098)", file=S, targets=TS,
         old="    s.functions == Snullfunctions && return Swrite_null(mem, from, size)\n",
         new=""),
    dict(id="LD3-8 closing a null stream fails (KILL: every row that closes it)", file=F, targets=TL,
         old="Sclose_null()::Int = 0\n",
         new="Sclose_null()::Int = -1\n"),
    dict(id="LD3-9 the read dispatch of a null stream reads one byte (KILL: none reachable: the stream is an output stream, no row reads it)", file=S, targets=TS,
         equivalent="read, not run: open_null_stream/1 makes an OUTPUT stream, so `S_read` is never called on it (get_char/2 refuses it with permission_error first: d101)",
         old="    s.functions == Snullfunctions && return Sread_null(mem, from, size)\n",
         new="    s.functions == Snullfunctions && return 1\n"),
]
