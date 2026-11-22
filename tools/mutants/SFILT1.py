# ORIGINAL: SFILT1's mutant list — no swipl-devel counterpart.
# tools/mutants/SFILT1.py — the mutation battery of the shared FILTER-STREAM extension (STREAMX: pl-stream.c Sset_filter, Snew over
# an AbstractSfilter, the dispatch of S_read/S_write/S_close to the filter, S_control and its callers Ssetenc/Sflush/S__seterror/Ssize,
# the S__close lock, the Sseterr/Sclearerr walks, Sfread/Sfwrite; src/os/pl-stream.jl), run ONCE, in CI (.github/workflows/mutation.yml;
# locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as O1B.py): `id`, `file`, `old` (must occur EXACTLY once), `new`,
# optional `equivalent` and `targets`. Killed by test/files/test_stream_filter_swipl.jl (rows f01-f14, named in each id's KILL).
# Verdicts: written by the battery, not yet run. The `old` strings were checked to occur exactly once at wip/stream-filter (a text count,
# no Julia): RE-FIT any that `tools/warm.sh fmt` rewrapped.
# NOT LISTED (each with its reason):
#   * Sfread's `chars <= avail` -> `<`: the whole buffered rest is then copied by the else branch and one more S__fillbuf runs, whose
#     result (EOF or one byte) is the answer's own: the count returned is the same; only the stream's end flag moves earlier. No row reads
#     the flag at that moment: NOT COVERED, not claimed equivalent.
#   * Sfread's `s.position !== nothing` -> `true`: a position-less stream read byte by byte through Sgetc gives the same bytes (a
#     different path to the same answer): EQUIVALENT-looking, NOT listed as a row.
#   * stream_file_name_propery's downstream walk (src/os/pl-file.jl): it needs the Prolog `stream_property(S, file_name(F))` of a filter
#     stream, which no Julia row can ask: left to the Prolog-level rows of the prolog_stream step.
#   * S__close's `Sunlock(s)` after the lock refusal: for a buffered stream it does nothing (an unbuffered output stream's bytes are
#     written out); no row builds an unbuffered filter: NOT COVERED.
# TARGETS (audit D-0238): the mutated code is the stream layer every stream goes through. The step's own file first, then the stream
# tests that call S__close, Sseterr, Sclearerr, Sflush, S_read, S_write (test_stream_swipl.jl, test_open_close_swipl.jl) and the redirects
# (with_output_to/2: test_with_output_to_swipl.jl; the wrapped streams: test_top1b_wrap_swipl.jl; test_s2a_swipl.jl); the first battery
# run prunes a target that does not pass on the unmutated tree.
TS = ["test/files/test_stream_filter_swipl.jl"]
TX = [
    "test/files/test_stream_swipl.jl", "test/files/test_open_close_swipl.jl", "test/core_lang/test_top1b_wrap_swipl.jl",
    "test/core_lang/test_with_output_to_swipl.jl", "test/core_lang/test_s2a_swipl.jl",
]
TARGETS = TS + TX
S = "src/os/pl-stream.jl"

MUTANTS = [
    # ── Sset_filter ──
    dict(id="SFILT1-A1 Sset_filter does not reference the filter: its count stays 0 while linked (KILL f04, f11)",
         file=S, targets=TS,
         old="        Sreference(filter)\n        Sreference(parent)\n",
         new="        Sreference(parent)\n"),
    dict(id="SFILT1-A2 Sset_filter does not set the filter's downstream: the unlink's assert on f.downstream fails (KILL f04, f01)",
         file=S, targets=TS,
         old="        filter.downstream = parent\n",
         new="        nothing\n"),
    dict(id="SFILT1-A3 Sset_filter does not set the parent's upstream: the parent is not locked and Sseterr does not reach the filter (KILL f03, f04, f05)",
         file=S, targets=TS,
         old="        parent.upstream = filter\n",
         new="        nothing\n"),
    dict(id="SFILT1-A4 Sset_filter's unlink does not release the filter: its count stays 1 (KILL f04, f11)",
         file=S, targets=TS,
         old="            Srelease(f)",
         new="            nothing"),
    dict(id="SFILT1-A5 Sset_filter's unlink does not release the parent: its count stays 1 (KILL f04, f11)",
         file=S, targets=TS,
         old="            Srelease(parent)\n",
         new="            nothing\n"),
    dict(id="SFILT1-A6 Sset_filter does not check the filter's magic: a closed filter is linked (KILL f04)",
         file=S, targets=TS,
         old="        filter.magic != SIO_MAGIC && return -1",
         new="        false && return -1"),
    dict(id="SFILT1-A7 Snew of a filter does not assert the function set: a wrong set is accepted (KILL f12)",
         file=S, targets=TS,
         old="    @assert functions == Sfilterfunctions\n",
         new="    nothing\n"),
    # ── the dispatch ──
    dict(id="SFILT1-B1 S_read_wrapped does not dispatch a filter stream to its read callback: the string reader answers (KILL f02, f08, f10)",
         file=S, targets=TS,
         old="    s.functions == Sfilterfunctions && return Sread_filter(s, mem, from, size)\n",
         new="    nothing\n"),
    dict(id="SFILT1-B2 S_write does not dispatch a filter stream to its write callback (KILL f01, f07, f10, f11)",
         file=S, targets=TS,
         old="    s.functions == Sfilterfunctions && return Swrite_filter(s, mem, from, size)\n",
         new="    nothing\n"),
    dict(id="SFILT1-B3 S_close_wrapped does not dispatch a filter stream to its close callback: the parent is never unlinked or closed (KILL f01, f02, f11)",
         file=S, targets=TS,
         old="    s.functions == Sfilterfunctions && return Sclose_filter(s)\n",
         new="    nothing\n"),
    dict(id="SFILT1-B4 Sclose_filter of a stream with no record answers -1 instead of 0 (KILL f12)",
         file=S, targets=TS,
         old="    f === nothing && return 0\n",
         new="    f === nothing && return -1\n"),
    dict(id="SFILT1-B5 Sread_filter of a stream with no record answers 0 (end of file) instead of -1 (KILL f12)",
         file=S, targets=TS,
         old="function Sread_filter(s::IOSTREAM, mem::Vector{UInt8}, from::Int, size::Int)::Int\n    f = s.filter\n    f === nothing && return -1\n",
         new="function Sread_filter(s::IOSTREAM, mem::Vector{UInt8}, from::Int, size::Int)::Int\n    f = s.filter\n    f === nothing && return 0\n"),
    # ── S_control and its callers ──
    dict(id="SFILT1-C1 Ssetenc does not forward SIO_SETENCODING to the control function: it is never asked (KILL f06)",
         file=S, targets=TS,
         old="        rc = S_control(s, SIO_SETENCODING, Ref(enc))\n",
         new="        rc = 0\n"),
    dict(id="SFILT1-C2 Ssetenc ignores a refusal of the control function (KILL f06)",
         file=S, targets=TS,
         old="        rc != SCONTROL_NONE && rc != 0 && return -1\n",
         new="        nothing\n"),
    dict(id="SFILT1-C3 Sflush does not ask for SIO_FLUSHOUTPUT (KILL f07)",
         file=S, targets=TS,
         old="            rc = S_control(s, SIO_FLUSHOUTPUT, nothing)\n",
         new="            rc = 0\n"),
    dict(id="SFILT1-C4 Sflush takes the control's -1 for success (KILL f07)",
         file=S, targets=TS,
         old="            rc != SCONTROL_NONE && rc < 0 && return -1\n",
         new="            nothing\n"),
    dict(id="SFILT1-C5 S__seterror does not ask for SIO_LASTERROR: the filter's own message is lost (KILL f08)",
         file=S, targets=TS,
         old="        if S_control(s, SIO_LASTERROR, msg) == 0\n",
         new="        if false\n"),
    dict(id="SFILT1-C6 Ssize does not ask for SIO_GETSIZE: -1 (KILL f09)",
         file=S, targets=TS,
         old="        S_control(s, SIO_GETSIZE, size) == 0 && return size[]\n",
         new="        nothing\n"),
    # ── the S__close lock, the walks ──
    dict(id="SFILT1-D1 S__close does not refuse a stream with a filter on it: the parent is closed under the filter (KILL f03)",
         file=S, targets=TS + TX,
         old="    if s.upstream !== nothing ",
         new="    if false "),
    dict(id="SFILT1-D2 Sseterr stops after the first stream: the filter on the parent does not see the error (KILL f03, f05)",
         file=S, targets=TS,
         old="        us = us.upstream\n",
         new="        us = nothing\n"),
    dict(id="SFILT1-D3 Sclearerr stops after the first stream: the parent the filter filters keeps its error (KILL f05)",
         file=S, targets=TS,
         old="        us = us.downstream\n    end\n    return nothing\nend\n\n# PORT: pl-stream.c Sset_exception",
         new="        us = nothing\n    end\n    return nothing\nend\n\n# PORT: pl-stream.c Sset_exception"),
    # ── Sfread, Sfwrite ──
    dict(id="SFILT1-E1 Sfread counts bytes, not elements: a size of 2 returns twice the count (KILL f14)",
         file=S, targets=TS,
         old="    return (size * elms - chars) ÷ size\nend\n\n# PORT: pl-stream.c Sfwrite",
         new="    return (size * elms - chars)\nend\n\n# PORT: pl-stream.c Sfwrite"),
    dict(id="SFILT1-E2 Sfwrite counts bytes, not elements (KILL f14)",
         file=S, targets=TS,
         old="        bi += 1\n        chars -= 1\n    end\n    return (size * elms - chars) ÷ size\nend\n\n# PORT: SWI-Stream.h SIO_RP_BLOCK",
         new="        bi += 1\n        chars -= 1\n    end\n    return (size * elms - chars)\nend\n\n# PORT: SWI-Stream.h SIO_RP_BLOCK"),
    dict(id="SFILT1-E3 Sfread has no size 0 guard: the element count divides by zero (KILL f14)",
         file=S, targets=TS,
         old="    size == 0 && return 0\n    chars = size * elms\n    bi = 1                                      # `buf`",
         new="    chars = size * elms\n    bi = 1                                      # `buf`"),
    dict(id="SFILT1-E4 Sfread's buffered branch does not advance the stream's buffer pointer after a full copy (KILL f14)",
         file=S, targets=TS,
         old="                    s.bufp += chars\n                    return elms\n",
         new="                    return elms\n"),
    dict(id="SFILT1-E5 Sfread's buffered branch does not advance the destination after the partial copy: the second chunk overwrites the first (KILL f14 big)",
         file=S, targets=TS,
         old="                    bi += avail\n",
         new="                    nothing\n"),
    # ── EQUIVALENT ──
    dict(id="SFILT1-Q1 S_control tests the function set before the filter: with the test removed the answer is the same (EQUIVALENT)",
         file=S, targets=TS,
         old="function S_control(s::IOSTREAM, op::Int, @nospecialize(arg))::Int\n    if s.functions == Sfilterfunctions\n",
         new="function S_control(s::IOSTREAM, op::Int, @nospecialize(arg))::Int\n    if true\n",
         equivalent="src/os/pl-stream.jl, S_control: `s.filter` is set only by Snew(::AbstractSfilter, ...), which asserts the function set is Sfilterfunctions, so a stream whose set is not Sfilterfunctions has `filter === nothing` and the next line returns SCONTROL_NONE as the removed test would. Read, not run."),
]
