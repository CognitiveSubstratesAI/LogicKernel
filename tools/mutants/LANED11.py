# ORIGINAL: lane D's mutant list (piece 11, ENC1) — no swipl-devel counterpart.
# tools/mutants/LANED11.py — ENC_ANSI in the stream layer: put_code, Scanrepresent, Sgetcode (pl-stream.c), read_pending_input and open/4's
# `encoding(text)` (pl-file.c), and the libc wrappers they call. Format: as LANED10.py. UNTESTED: nothing was compiled. Every `old` occurs exactly once
# in its file (python3 -I ~/code/lk-t27-scratch/oldscan.py LANED11).
# TARGETS: test_enc_ansi_swipl.jl (rows u01-u23 under C.UTF-8, c01-c12 under C, the libc wrapper rows) is the only file that opens a stream in
# `text`; test_lane_d_swipl.jl, test_open_close_swipl.jl and test_string_swipl.jl reach put_code/Sgetcode/read_pending_input/openStream with the other
# encodings and are listed because they run the shared code around the mutated arms (D-0238).
# EQUIVALENT: LD11-3, LD11-5 (the state of a stateless locale): the locales a test can set here (C.UTF-8, C) have no shift state, a fresh `mbstate_t`
# converts as the stream's does; the stream's state is upstream's design for a stateful locale (ISO-2022) the test host lacks.
TL = ["test/core_lang/test_enc_ansi_swipl.jl", "test/core_lang/test_lane_d_swipl.jl", "test/files/test_open_close_swipl.jl", "test/core_lang/test_string_swipl.jl"]
TARGETS = TL
F = "src/os/pl-file.jl"
G = "src/os/pl-stream.jl"
MUTANTS = [
    dict(id="LD11-1 put_code: only the first byte of a multibyte character is written (KILL: u01, u17-u21)", file=G, targets=TL,
         old="            for x in mb\n                put_byte(Int(x), s) < 0 && return -1\n            end\n",
         new="            put_byte(Int(mb[1]), s) < 0 && return -1\n"),
    dict(id="LD11-2 put_code: an unrepresentable character is dropped silently (KILL: c01, c07, c10)", file=G, targets=TL,
         old="        if mb === nothing\n            reperror(c, s) < 0 && return -1\n        else\n",
         new="        if mb === nothing\n        else\n"),
    dict(id="LD11-3 put_code: a fresh mbstate for every character (stateless locales only)", file=G, targets=TL,
         old="        mb = _wcrtomb(c, stream_mbstate!(s))\n",
         new="        mb = _wcrtomb(c, zeros(UInt64, MBSTATE_WORDS))\n",
         equivalent="C.UTF-8 and C have no shift state: a fresh mbstate_t encodes every character as the stream's does (the stream's state is for a stateful locale)"),
    dict(id="LD11-4 Scanrepresent: the answer is inverted (KILL: u17-u21 quoting rows, c06-c09, the Scanrepresent unit rows)", file=G, targets=TL,
         old="        return _wcrtomb(c, zeros(UInt64, MBSTATE_WORDS)) === nothing ? -1 : 0   # a fresh `mbstate_t`, as upstream's local `state`\n",
         new="        return _wcrtomb(c, zeros(UInt64, MBSTATE_WORDS)) === nothing ? 0 : -1   # a fresh `mbstate_t`, as upstream's local `state`\n"),
    dict(id="LD11-5 Scanrepresent: the stream's own mbstate instead of a fresh one (stateless locales only)", file=G, targets=TL,
         old="        return _wcrtomb(c, zeros(UInt64, MBSTATE_WORDS)) === nothing ? -1 : 0   # a fresh `mbstate_t`, as upstream's local `state`\n",
         new="        return _wcrtomb(c, stream_mbstate!(s)) === nothing ? -1 : 0   # a fresh `mbstate_t`, as upstream's local `state`\n",
         equivalent="a failed or complete wcrtomb leaves a stateless locale's mbstate_t zero: both states give the same answer"),
    dict(id="LD11-6 Sgetcode: an illegal sequence is not an error, the next byte is read (KILL: u06, u08, c03)", file=G, targets=TL,
         old="                elseif rc == -1\n                    Sseterr(s, SIO_WARN, \"Illegal multibyte Sequence\")\n",
         new="                elseif rc == -3\n                    Sseterr(s, SIO_WARN, \"Illegal multibyte Sequence\")\n"),
    dict(id="LD11-7 Sgetcode: an illegal sequence reads as end of file (KILL: u06, u08, c03: 65533 expected)", file=G, targets=TL,
         old="                    Sseterr(s, SIO_WARN, \"Illegal multibyte Sequence\")\n                    c = UTF8_MALFORMED_REPLACEMENT              # mberr:\n",
         new="                    Sseterr(s, SIO_WARN, \"Illegal multibyte Sequence\")\n                    c = -1                                      # mberr:\n"),
    dict(id="LD11-8 Sgetcode: a fresh mbstate for every byte, a multibyte character never completes (KILL: u02, u07, u10, u14)", file=G, targets=TL,
         old="                rc, wc = _mbrtowc(b1, 1, 1, st)\n",
         new="                rc, wc = _mbrtowc(b1, 1, 1, zeros(UInt64, MBSTATE_WORDS))\n"),
    dict(id="LD11-9 Sgetcode: a NUL byte (rc 0) is not a character (KILL: u05, u23, c12)", file=G, targets=TL,
         old="                if rc == 1 || rc == 0\n",
         new="                if rc == 1\n"),
    dict(id="LD11-10 Sgetcode: a lone lead byte at end of file reads as the replacement (KILL: u04)", file=G, targets=TL,
         old="                    if n != 0\n                        Sseterr(s, SIO_WARN, \"EOF in multibyte Sequence\")\n",
         new="                    if true\n                        Sseterr(s, SIO_WARN, \"EOF in multibyte Sequence\")\n"),
    dict(id="LD11-11 _mbrtowc: an incomplete sequence (-2) is an illegal one (KILL: u02, u07, u10)", file=G, targets=TL,
         old="    rc == typemax(Csize_t) - 1 && return (-2, 0)                # (size_t)-2\n",
         new="    rc == typemax(Csize_t) - 1 && return (-1, 0)                # (size_t)-2\n"),
    dict(id="LD11-12 _wcrtomb: an unrepresentable character yields no bytes instead of `nothing` (KILL: c01, c07, the unit rows)", file=G, targets=TL,
         old="    n == typemax(Csize_t) && return nothing\n",
         new="    n == typemax(Csize_t) && return UInt8[]\n"),
    dict(id="LD11-13 _mbsnrtowcs_count: an illegal sequence counts as zero characters (KILL: u13, c05, c11, the unit rows)", file=G, targets=TL,
         old="    rc == typemax(Csize_t) && return -1\n    return Int(rc)\n",
         new="    rc == typemax(Csize_t) && return 0\n    return Int(rc)\n"),
    dict(id="LD11-14 stream_mbstate!: a new state on every call (KILL: the stream_mbstate! unit row: the state is made once)", file=G, targets=TL,
         old="    st = s.mbstate\n    if st === nothing\n",
         new="    st = s.mbstate\n    if true\n"),
    dict(id="LD11-15 read_pending_input: the count runs on the stream's state, not on a copy (KILL: u11: the partial tail poisons the decoding)", file=F, targets=TL,
         old="        count = _mbsnrtowcs_count(buf, n, s0)\n",
         new="        count = _mbsnrtowcs_count(buf, n, st)\n"),
    dict(id="LD11-16 read_pending_input: an illegal sequence does not fail the call (KILL: u13, c05, c11)", file=F, targets=TL,
         old="        if count == -1\n            Sseterr(s, SIO_WARN, \"Illegal multibyte Sequence\")\n",
         new="        if count == -5\n            Sseterr(s, SIO_WARN, \"Illegal multibyte Sequence\")\n"),
    dict(id="LD11-17 read_pending_input: a multibyte character advances one byte (KILL: u10, u14, u15)", file=F, targets=TL,
         old="                us += rc                                      # (upstream's `us += mbrtowc(...)`: a NUL character is rc 0, so `us` stays)\n",
         new="                us += 1                                       # (upstream's `us += mbrtowc(...)`: a NUL character is rc 0, so `us` stays)\n"),
    dict(id="LD11-18 read_pending_input: the byte count is one too large (KILL: u10, u11, u14, u15, u16)", file=F, targets=TL,
         old="            p !== nothing && (p.byteno = pos0.byteno + (us - 1))\n\n            re_buffer(s, buf, us, es - us)\n        end\n    elseif enc == ENC_UTF8",
         new="            p !== nothing && (p.byteno = pos0.byteno + us)\n\n            re_buffer(s, buf, us, es - us)\n        end\n    elseif enc == ENC_UTF8"),
    dict(id="LD11-19 read_pending_input: the unread tail is not pushed back (KILL: u11: the incomplete bytes stay pending, byte_count 1)", file=F, targets=TL,
         old="\n            re_buffer(s, buf, us, es - us)\n        end\n    elseif enc == ENC_UTF8",
         new="\n        end\n    elseif enc == ENC_UTF8"),
]
