# ORIGINAL: STREAMS-A's mutant list — no swipl-devel counterpart.
# tools/mutants/STREAMSA.py — the mutation battery of STREAMS-A (os/pl-file.c, swipl-devel 18168e62: get/put/get0/skip/get_nonblank,
# put_byte, get_byte, peek (the byte branch), set_input, set_output, byte_count, character_count, fill_buffer, copy_stream_data,
# peek_string), run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as
# S2A.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`. "Aimed by": each id names the
# rows of test/files/test_streams_a_swipl.jl (sa001-sa142) written to kill it. Verdicts: written by the battery, not yet run; the
# rows themselves were never run either (the gate shows which kill).
# The `old` strings are written in the repo's formatted style BEFORE `tools/warm.sh fmt` ran (the writing agent had no daemon):
# RE-FIT any that fmt rewraps (mutate_drive.py refuses a string that does not occur exactly once). Every `old` was checked to occur
# exactly once in src/os/pl-file.jl at wip/streams-a (a text count, python3 -I, no Julia).
# REPLAY (onto the Edinburgh I/O line, pl-file.jl as lane D wrote it): every `old` below was re-fitted to that text; the targets add
# lane D's and the Edinburgh I/O files (they exercise the same predicates).
# TARGETS (audit D-0238): the step's own file first (a run stops at the first target that decides), then every file that reaches
# pl-file.jl's stream code: the S2a and LB5 rows (peek, skip, get_char/2 share the handles), the stream, open/close and
# process-stream files.
TS = ["test/files/test_streams_a_swipl.jl"]
TF = ["test/core_lang/test_lane_d_swipl.jl", "test/core_lang/test_edinburgh_io_swipl.jl", "test/core_lang/test_s2a_swipl.jl", "test/core_lang/test_lb5_swipl.jl", "test/files/test_stream_swipl.jl",
      "test/files/test_open_close_swipl.jl", "test/files/test_process_streams_swipl.jl"]
ALL = TS + TF
TARGETS = ALL                                        # the baseline's targets (mutate_ci.py plan reads TARGETS; pre-push check 5)
F = "src/os/pl-file.jl"
MUTANTS = [
    # ── get_nonblank (get/1,2) ──
    dict(id="SA-G1 get_nonblank returns the first character, layout or not (aimed by sa003, sa014)", file=F, targets=ALL,
         old="            isBlankW(c) || return PL_unify_integer(ld, chr, c)\n",
         new="            return PL_unify_integer(ld, chr, c)\n"),
    dict(id="SA-G2 get_nonblank answers 0, not -1, at the end of the stream (aimed by sa004, sa005)", file=F, targets=ALL,
         old="                PL_unify_integer(ld, chr, -1) || return false\n",
         new="                PL_unify_integer(ld, chr, 0) || return false\n"),
    # ── put_byte ──
    dict(id="SA-B1 put_byte accepts 256 (aimed by sa040, sa047)", file=F, targets=ALL,
         old="    if c === nothing || c < 0 || c > 255\n",
         new="    if c === nothing || c < 0 || c > 256\n"),
    dict(id="SA-B2 put_byte accepts -1 (aimed by sa041)", file=F, targets=ALL,
         old="    if c === nothing || c < 0 || c > 255\n",
         new="    if c === nothing || c < -1 || c > 255\n"),
    dict(id="SA-B3 put_byte writes to a text stream too (aimed by sa044, sa045)", file=F, targets=ALL,
         old="    s = getOutputStream(ld, stream, S_BINARY)       # getBinaryOutputStream\n",
         new="    s = getOutputStream(ld, stream, S_DONTCARE)     # getBinaryOutputStream\n"),
    # ── get_byte2 ──
    dict(id="SA-B4 get_byte reads a text stream too (aimed by sa052, sa053)", file=F, targets=ALL,
         old="    s = getInputStream(ld, in, S_BINARY)            # getBinaryInputStream\n    if s !== nothing\n        c = Sgetc(s)\n",
         new="    s = getInputStream(ld, in, S_DONTCARE)          # getBinaryInputStream\n    if s !== nothing\n        c = Sgetc(s)\n"),
    dict(id="SA-B5 get_byte(S, a) fails instead of raising the type error (aimed by sa054)", file=F, targets=ALL,
         old="        PL_get_char(ld, chr)                        # set type-error\n    end\n    return false\nend\n\n# PORT: pl-file.c get_byte2 as pl_get_byte2_va\n",
         new="        nothing                                     # set type-error\n    end\n    return false\nend\n\n# PORT: pl-file.c get_byte2 as pl_get_byte2_va\n"),
    dict(id="SA-B6 get_byte(S, -1) before the end raises the type error: the eof branch is -2 (aimed by sa141: -1 offered before the end fails, the byte is consumed; sa142 pins the end_of_file atom half, which this mutant leaves in place)",
         file=F, targets=ALL,
         old="        (i == -1 || (a !== nothing && sym_key(a) == sym_key(mk_sym(T, :end_of_file)))) &&\n            return false\n        PL_get_char(ld, chr)                        # set type-error\n    end\n    return false\nend\n\n# PORT: pl-file.c get_byte2 as pl_get_byte2_va\n",
         new="        (i == -2 || (a !== nothing && sym_key(a) == sym_key(mk_sym(T, :end_of_file)))) &&\n            return false\n        PL_get_char(ld, chr)                        # set type-error\n    end\n    return false\nend\n\n# PORT: pl-file.c get_byte2 as pl_get_byte2_va\n"),
    # ── peek (byte branch, unbuffered refusal) ──
    dict(id="SA-K1 peek_byte takes a text stream (aimed by sa071)", file=F, targets=ALL,
         old="    s = getInputStream(ld, stream, how === :byte ? S_BINARY : S_TEXT)\n",
         new="    s = getInputStream(ld, stream, S_TEXT)\n"),
    dict(id="SA-K2 peek on an unbuffered stream is allowed (aimed by sa061, sa072)", file=F, targets=ALL,
         old="    if (s.flags & SIO_NBUF) != 0 || (s.bufsize != 0 && s.bufsize < UNDO_SIZE)   # PL_MB_LEN_MAX\n",
         new="    if (s.bufsize != 0 && s.bufsize < UNDO_SIZE)   # PL_MB_LEN_MAX\n"),
    dict(id="SA-K3 peek_byte keeps the byte it read: no Sungetc (aimed by sa050, sa060)", file=F, targets=ALL,
         old="        c != EOF && Sungetc(c, s)\n",
         new="        nothing\n"),
    dict(id="SA-K4 peek_byte leaves the byte position after the byte it unread (aimed by sa051)", file=F, targets=ALL,
         old="        p.byteno, p.charno, p.lineno, p.linepos, p.esc_state = oldpos.byteno,\n        oldpos.charno, oldpos.lineno, oldpos.linepos, oldpos.esc_state          # s->posbuf = pos\n",
         new="        p.byteno, p.charno, p.lineno, p.linepos, p.esc_state = p.byteno,\n        oldpos.charno, oldpos.lineno, oldpos.linepos, oldpos.esc_state          # s->posbuf = pos\n"),
    # ── set_input, set_output ──
    dict(id="SA-S1 set_input takes an output stream (aimed by sa084, sa082, sa089)", file=F, targets=ALL,
         old="    s = getInputStream(ld, PL__t0, S_DONTCARE)\n    if s !== nothing\n        setStandardStream(ld, SNO_CURRENT_INPUT, s)\n",
         new="    s = getOutputStream(ld, PL__t0, S_DONTCARE)\n    if s !== nothing\n        setStandardStream(ld, SNO_CURRENT_INPUT, s)\n"),
    dict(id="SA-S2 set_input sets the current output (aimed by sa082, sa060, sa089)", file=F, targets=ALL,
         old="    setStandardStream(ld, SNO_CURRENT_INPUT, s)\n",
         new="    setStandardStream(ld, SNO_CURRENT_OUTPUT, s)\n"),
    dict(id="SA-S3 set_output takes an input stream (aimed by sa083, sa088)", file=F, targets=ALL,
         old="    s = getOutputStream(ld, PL__t0, S_DONTCARE)\n    if s !== nothing\n        setStandardStream(ld, SNO_CURRENT_OUTPUT, s)\n",
         new="    s = getInputStream(ld, PL__t0, S_DONTCARE)\n    if s !== nothing\n        setStandardStream(ld, SNO_CURRENT_OUTPUT, s)\n"),
    dict(id="SA-S4 set_output sets the current input (aimed by sa088, sa091, sa093)", file=F, targets=ALL,
         old="        setStandardStream(ld, SNO_CURRENT_OUTPUT, s)\n        return FTRUE\n    end\n    return FFALSE\nend\n",
         new="        setStandardStream(ld, SNO_CURRENT_INPUT, s)\n        return FTRUE\n    end\n    return FFALSE\nend\n"),
    # ── byte_count, character_count ──
    dict(id="SA-C1 byte_count answers the character position (aimed by sa133, sa134)", file=F, targets=ALL,
         old="    n = (s.position::IOPOS).byteno\n",
         new="    n = (s.position::IOPOS).charno\n"),
    dict(id="SA-C2 character_count answers the byte position (aimed by sa133, sa134)", file=F, targets=ALL,
         old="    n = (s.position::IOPOS).charno\n",
         new="    n = (s.position::IOPOS).byteno\n"),
    # ── fill_buffer ──
    dict(id="SA-F1 fill_buffer fills an unbuffered stream without the permission error (aimed by sa097)", file=F, targets=ALL,
         old="        if (s.flags & SIO_NBUF) != 0\n            streamStatus(ld, s) || return FFALSE",
         new="        if false\n            streamStatus(ld, s) || return FFALSE"),
    dict(id="SA-F2 fill_buffer consumes the first character: the buffer pointer is not stepped back (aimed by sa095, sa099, sa101)",
         file=F, targets=ALL,
         old="            s.bufp -= 1\n        end\n        return streamStatus(ld, s) ? FTRUE : FFALSE              # PL_release_stream(s)\n    end\n",
         new="            nothing\n        end\n        return streamStatus(ld, s) ? FTRUE : FFALSE              # PL_release_stream(s)\n    end\n"),
    # ── copy_stream_data ──
    dict(id="SA-D1 copy_stream_data/3 ignores the length: copies all (aimed by sa103, sa104, sa106)", file=F, targets=ALL,
         old="    if len == 0\n        while (c = Sgetcode(i)) != EOF\n",
         new="    if true\n        while (c = Sgetcode(i)) != EOF\n"),
    dict(id="SA-D2 copy_stream_data/2 reads a length it does not have: the all-characters branch is never taken (aimed by sa102, sa109)",
         file=F, targets=ALL,
         old="    if len == 0\n        while (c = Sgetcode(i)) != EOF\n",
         new="    if false\n        while (c = Sgetcode(i)) != EOF\n"),
    dict(id="SA-D3 copy_stream_data/3 copies one character more than the length (aimed by sa103, sa104, sa117)", file=F, targets=ALL,
         old="        while n > 0 && (c = Sgetcode(i)) != EOF\n",
         new="        while n >= 0 && (c = Sgetcode(i)) != EOF\n"),
    # ── peek_string ──
    dict(id="SA-P1 peek_string answers one character fewer than asked (aimed by sa118, sa122, sa127)", file=F, targets=ALL,
         old="                rc = PL_unify_text_range(ld, A3, text, 0, len, PL_STRING)\n",
         new="                rc = PL_unify_text_range(ld, A3, text, 0, len - 1, PL_STRING)\n"),
    dict(id="SA-P2 peek_string needs one character more than asked before answering from the buffer (aimed by sa118, sa129)",
         file=F, targets=ALL,
         old="            if text.length >= len\n",
         new="            if text.length > len\n"),
    dict(id="SA-P3 peek_string leaves the end-of-file flag set after the rest-of-stream answer (aimed by sa128, sa119)",
         file=F, targets=ALL,
         old="            s.flags &= ~SIO_FEOF\n\n            text = peek_pending_text(s)\n",
         new="            nothing\n\n            text = peek_pending_text(s)\n"),
]

if __name__ == "__main__":
    import sys
    if "--check" in sys.argv:
        import os
        cache, bad = {}, 0
        for m in MUTANTS:
            src = cache.setdefault(m["file"], open(m["file"]).read())
            n = src.count(m["old"])
            ok = n == 1 and m["new"] != m["old"] and all(os.path.exists(x) for x in m.get("targets", TARGETS))
            ok = ok and (m.get("equivalent") is None or len(m["equivalent"]) > 10)
            bad += not ok
            print(("ok  " if ok else "BAD ") + m["id"][:60] + ("" if n == 1 else "  count=%d" % n))
        print("%d mutants, %d bad" % (len(MUTANTS), bad))
        sys.exit(1 if bad else 0)
