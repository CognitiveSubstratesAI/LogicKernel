# ORIGINAL: SFILT2's mutant list — no swipl-devel counterpart.
# tools/mutants/SFILT2.py — the mutation battery of the stream-layer pieces the C packages (clib prolog_stream.c, hash_stream.c)
# need beyond SFILT1's filter streams: (a) pl-stream.c Sread_pending, Spending, Sfileno (S__fileno, the `fileno` field),
# (b) ENC_WCHAR in Sgetcode/Sputcode, (c) Sset_exception and the pending-exception record (src/os/pl-stream.jl), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format as SFILT1.py: `id`, `file`, `old` (EXACTLY once), `new`,
# optional `equivalent` and `targets`. Verdicts: written by the battery, not yet run. The `old` strings were checked to occur exactly
# once at wip/stream-filter (a text count, no Julia): RE-FIT any that `tools/warm.sh fmt` rewrapped.
# TARGETS (audit D-0238): the pieces' own test files first (a: test_stream_pending_swipl.jl), then the files that exercise the same
# code: the filter tests (Snew of a filter calls S__fileno), and the stream tests whose streams go through Sgetcode/Sputcode/S__close.
TP = ["test/files/test_stream_pending_swipl.jl"]
TX = [
    "test/files/test_stream_filter_swipl.jl", "test/files/test_stream_swipl.jl", "test/files/test_open_close_swipl.jl",
    "test/core_lang/test_top1b_wrap_swipl.jl", "test/core_lang/test_with_output_to_swipl.jl", "test/core_lang/test_s2a_swipl.jl",
]
TARGETS = TP + TX
S = "src/os/pl-stream.jl"

MUTANTS = [
    # ── (a) Sread_pending ──
    dict(id="SFILT2-A1 Sread_pending's filled byte is lost: buf[1] is 0 (KILL p01, p03)",
         file=S, targets=TP,
         old="        buf[1] = c % UInt8\n",
         new="        buf[1] = 0x00\n"),
    dict(id="SFILT2-A2 Sread_pending does not shrink the limit by the filled byte: one byte too many (KILL p02)",
         file=S, targets=TP,
         old="        limit -= 1\n        done = 1\n",
         new="        done = 1\n"),
    dict(id="SFILT2-A3 Sread_pending does not count the filled byte: done stays 0 (KILL p01, p02, p03)",
         file=S, targets=TP,
         old="        limit -= 1\n        done = 1\n",
         new="        limit -= 1\n"),
    dict(id="SFILT2-A4 Sread_pending does not cap the copy at the limit (KILL p02)",
         file=S, targets=TP,
         old="    n > limit && (n = limit)\n",
         new="    nothing\n"),
    dict(id="SFILT2-A5 Sread_pending always blocks: a fresh stream is filled without SIO_RP_BLOCK (KILL p05)",
         file=S, targets=TP,
         old="    if s.bufp >= s.limitp && (flags & SIO_RP_BLOCK) != 0\n",
         new="    if s.bufp >= s.limitp\n"),
    dict(id="SFILT2-A6 Sread_pending always updates the position: SIO_RP_NOPOS is ignored (KILL p04)",
         file=S, targets=TP,
         old="    if s.position !== nothing && (flags & SIO_RP_NOPOS) == 0\n",
         new="    if s.position !== nothing\n"),
    dict(id="SFILT2-A7 Sread_pending does not count characters (KILL p01, p02, p03, p05)",
         file=S, targets=TP,
         old="            p.charno += 1\n",
         new="            nothing\n"),
    dict(id="SFILT2-A8 Sread_pending does not advance the line position (KILL p01, p02)",
         file=S, targets=TP,
         old="            update_linepos(s, Int(buf[i]))\n",
         new="            nothing\n"),
    dict(id="SFILT2-A9 Sread_pending does not consume the bytes it delivered (KILL p02, p05)",
         file=S, targets=TP,
         old="    s.bufp += n\n    return done + n\n",
         new="    return done + n\n"),
    dict(id="SFILT2-A10 Sread_pending answers the fill's -1 at a clean end of file instead of 0 (KILL p01)",
         file=S, targets=TP,
         old="            (s.flags & SIO_FEOF) != 0 && Sfpasteof(s) != 1 && return 0\n",
         new="            false && return 0\n"),
    dict(id="SFILT2-A11 Sread_pending fills only when the buffer is overrun, not when it is empty (KILL p01)",
         file=S, targets=TP,
         old="    if s.bufp >= s.limitp && (flags & SIO_RP_BLOCK) != 0\n",
         new="    if s.bufp > s.limitp && (flags & SIO_RP_BLOCK) != 0\n"),
    dict(id="SFILT2-A12 Sread_pending's position loop leaves out the filled byte (KILL p03)",
         file=S, targets=TP,
         old="        for i in 1:(done + n)\n",
         new="        for i in 1:n\n"),
    # ── (a) Spending ──
    dict(id="SFILT2-B1 Spending always asks the control function, even with bytes buffered (KILL p06)",
         file=S, targets=TP,
         old="    s.bufp < s.limitp && return s.limitp - s.bufp\n    pending = Ref(0)\n",
         new="    pending = Ref(0)\n"),
    dict(id="SFILT2-B2 Spending is off by one over the buffered bytes (KILL p02, p06)",
         file=S, targets=TP,
         old="    s.bufp < s.limitp && return s.limitp - s.bufp\n    pending = Ref(0)\n",
         new="    s.bufp < s.limitp && return s.limitp - s.bufp + 1\n    pending = Ref(0)\n"),
    dict(id="SFILT2-B3 Spending takes the control function's answer when it refuses (KILL p06)",
         file=S, targets=TP,
         old="    S_control(s, SIO_GETPENDING, pending) == 0 && return pending[]\n",
         new="    S_control(s, SIO_GETPENDING, pending) != 0 && return pending[]\n"),
    dict(id="SFILT2-B4 Spending drops the control function's number (KILL p06)",
         file=S, targets=TP,
         old="    S_control(s, SIO_GETPENDING, pending) == 0 && return pending[]\n",
         new="    S_control(s, SIO_GETPENDING, pending) == 0 && return 0\n"),
    # ── (a) Sfileno, S__fileno ──
    dict(id="SFILT2-C1 Sfileno answers the cache of a closed stream (KILL p07)",
         file=S, targets=TP,
         old="    s.magic != SIO_MAGIC && return -1           # errno = EINVAL\n    s.fileno >= 0 && return s.fileno\n",
         new="    s.fileno >= 0 && return s.fileno\n"),
    dict(id="SFILT2-C2 Sfileno treats descriptor 0 as none (KILL p07)",
         file=S, targets=TP,
         old="    s.fileno >= 0 && return s.fileno\n",
         new="    s.fileno > 0 && return s.fileno\n"),
    dict(id="SFILT2-C3 S__fileno takes the control function's number when it refuses (KILL p07)",
         file=S, targets=TP,
         old="        S_control(s, SIO_GETFILENO, n) == 0 && return n[]\n",
         new="        S_control(s, SIO_GETFILENO, n) != 0 && return n[]\n"),
    dict(id="SFILT2-C4 Snew of a filter does not cache the file number (KILL p07)",
         file=S, targets=TP,
         old="    s.fileno = S__fileno(s)\n",
         new="    nothing\n"),
    dict(id="SFILT2-C5 S__fileno asks the control function of a closed stream (KILL p07)",
         file=S, targets=TP,
         old="    if s.magic == SIO_MAGIC\n        n = Ref(0)\n",
         new="    if true\n        n = Ref(0)\n"),
    dict(id="SFILT2-C6 a stream starts with file number 0, not none (KILL p07)",
         file=S, targets=TP,
         old="        nothing, nothing, nothing, -1\n    )\n",
         new="        nothing, nothing, nothing, 0\n    )\n"),
    # (b) rows below: ENC_WCHAR; (c) rows below: Sset_exception
]

if __name__ == "__main__":     # the text check: every `old` once, new != old
    import sys
    src = {}
    bad = 0
    for m in MUTANTS:
        t = src.setdefault(m["file"], open(m["file"]).read())
        if t.count(m["old"]) != 1 or m["new"] == m["old"]:
            print("BAD", m["id"], t.count(m["old"]))
            bad += 1
    print(len(MUTANTS), "rows,", bad, "bad")
    sys.exit(1 if bad else 0)
