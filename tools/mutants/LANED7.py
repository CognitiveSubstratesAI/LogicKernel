# ORIGINAL: lane D's mutant list (piece 7) — no swipl-devel counterpart.
# tools/mutants/LANED7.py — the mutation battery of lane D piece 7 (relay 6): peek_string/3, copy_stream_data/2,3
# (pl-file.c), then the groups after them. Format: as LANED6.py. Killed by test/core_lang/test_lane_d_swipl.jl (rows d254 on).
# UNTESTED: nothing was compiled. Every `old` was checked to occur exactly once in its file at wip/lane-d.
# TARGETS: only test_lane_d_swipl.jl reaches peek_string / copy_stream_data (the other test files use neither).
TL = ["test/core_lang/test_lane_d_swipl.jl"]
TARGETS = TL
F = "src/os/pl-file.jl"
T = "src/os/pl-text.jl"
MUTANTS = [
    dict(id="LD7-1 peek_string: the length compare is strict (KILL: d254-d260 where the text has exactly Len characters)", file=F, targets=TL,
         old='            if text.length >= len\n                rc = PL_unify_text_range',
         new='            if text.length > len\n                rc = PL_unify_text_range'),
    dict(id="LD7-2 peek_string: the buffer is not doubled when full (KILL: d270-d272)", file=F, targets=TL,
         old='            Ssetbuffer(s, nothing, s.bufsize * 2)\n',
         new='            Ssetbuffer(s, nothing, s.bufsize)\n'),
    dict(id="LD7-3 peek_string: the EOF flag stays set after the last fill (KILL: d261, d284)", file=F, targets=TL,
         old='            s.flags &= ~SIO_FEOF\n\n            text = peek_pending_text(s)\n',
         new='            text = peek_pending_text(s)\n'),
    dict(id="LD7-4 peek_string: the fill leaves its byte consumed (KILL: d254, d270)", file=F, targets=TL,
         old='        s.bufp -= 1\n    end\nend\n\n# PORT: pl-file.c copy_stream_data\n',
         new='    end\nend\n\n# PORT: pl-file.c copy_stream_data\n'),
    dict(id="LD7-5 peek_string: a stream error is not reported (KILL: d280, d281)", file=F, targets=TL,
         old='            Sferror(s) != 0 && return streamStatus(ld, s) ? FTRUE : FFALSE\n\n            s.flags &= ~SIO_FEOF',
         new='            s.flags &= ~SIO_FEOF'),
    dict(id="LD7-6 peek_pending_text: a wchar stream counts bytes (KILL: no row peeks a wchar stream: equivalent for the rows)", file=F, targets=TL, eq=True,
         old='s.encoding == ENC_WCHAR ? n ÷ 4 : n',
         new='n'),
    dict(id="LD7-7 PL_canonicalise_text: the UTF-16 length counts units (no row: the pin has no oracle for UTF-16 peek_string, see DIVERGES)", file=T, targets=TL, eq=True,
         old='            text.length = r.encoding === ENC_WCHAR ? length(r.text) ÷ 4 : length(r.text)\n',
         new='            text.length = length(r.text)\n'),
    dict(id="LD7-8 copy_stream_data: len 0 is a one-character copy (KILL: d286, d288)", file=F, targets=TL,
         old='    if len == 0\n        while (c = Sgetcode(i)) != EOF',
         new='    if len != 0\n        while (c = Sgetcode(i)) != EOF'),
    dict(id="LD7-9 copy_stream_data: the length loop runs once more (KILL: d287)", file=F, targets=TL,
         old='        while n > 0 && (c = Sgetcode(i)) != EOF\n',
         new='        while n >= 0 && (c = Sgetcode(i)) != EOF\n'),
    dict(id="LD7-10 copy_stream_data: the input stream status is not checked (KILL: unknown, a stream error after a copy: d308/d309 if they set one)", file=F, targets=TL,
         old='    rc = streamStatus(ld, i) && rc\n',
         new='    rc = rc\n'),
    dict(id="LD7-11 copy_stream_data: the output stream status is not checked (KILL: unknown, as LD7-10)", file=F, targets=TL,
         old='    rc = streamStatus(ld, o)\n    rc = streamStatus',
         new='    rc = true\n    rc = streamStatus'),
    dict(id="LD7-12 the registration of peek_string/3 is gone (KILL: d254-d285)", file=F, targets=TL,
         old='    PL_extension("peek_string", 3, pl_peek_string3_va, PL_FA_VARARGS),\n',
         new=''),
    dict(id="LD7-13 the registration of copy_stream_data/3 is gone (KILL: d287-d289)", file=F, targets=TL,
         old='    PL_extension("copy_stream_data", 3, pl_copy_stream_data3_va, PL_FA_VARARGS),\n',
         new=''),
    dict(id="LD7-14 the registration of copy_stream_data/2 is gone (KILL: d286)", file=F, targets=TL,
         old='    PL_extension("copy_stream_data", 2, pl_copy_stream_data2_va, PL_FA_VARARGS),\n',
         new=''),
]
