# ORIGINAL: lane D's mutant list (piece 4) — no swipl-devel counterpart.
# tools/mutants/LANED4.py — the mutation battery of lane D piece 4, group S2b-1 (pl-file.c stream_pair/3, the pair arm of
# get_stream_handle, the pair arm of pl_close). Format: as LANED1.py. Killed by test/core_lang/test_lane_d_swipl.jl rows d109-d127
# (and test_open_close_swipl.jl / test_set_stream rows where they close or select a pair). UNTESTED: nothing was compiled.
# Every `old` was checked to occur exactly once in its file at wip/lane-d (a text count, no Julia).
TL = ["test/core_lang/test_lane_d_swipl.jl"]
TS = ["test/core_lang/test_lane_d_swipl.jl", "test/files/test_open_close_swipl.jl", "test/files/test_stream_swipl.jl"]
TARGETS = TS
F = "src/os/pl-file.jl"
MUTANTS = [
    dict(id="LD4-1 an output request on a pair picks the read stream (KILL: d112, d126)", file=F, targets=TS,
         old="                if (flags & SH_OUTPUT) != 0\n                    sn = ref.write\n",
         new="                if (flags & SH_OUTPUT) != 0\n                    sn = ref.read\n"),
    dict(id="LD4-2 an input request on a pair picks the write stream (KILL: d111, d125)", file=F, targets=TS,
         old="                elseif (flags & SH_INPUT) != 0\n                    sn = ref.read\n",
         new="                elseif (flags & SH_INPUT) != 0\n                    sn = ref.write\n"),
    dict(id="LD4-3 the flag error_ambiguous_stream_pair is read inverted (KILL: d117, d118)", file=F, targets=TL,
         old="                    if truePrologFlag(ld, PLFLAG_ERROR_AMBIGUOUS_STREAM_PAIR)\n",
         new="                    if !truePrologFlag(ld, PLFLAG_ERROR_AMBIGUOUS_STREAM_PAIR)\n"),
    dict(id="LD4-4 the ambiguous-pair warning continues with the write stream (KILL: d127: the read side has seen a newline, the write side has not)", file=F, targets=TL,
         old="                        ) || return nothing\n                        sn = ref.read\n",
         new="                        ) || return nothing\n                        sn = ref.write\n"),
    dict(id="LD4-5 an ambiguous request on a pair without the flag fails after the warning (KILL: d117)", file=F, targets=TL,
         old="                        ) || return nothing\n                        sn = ref.read\n",
         new="                        ) || return nothing\n                        return nothing\n"),
    dict(id="LD4-6 closing a pair closes the write half only (KILL: d125, d124, d126)", file=F, targets=TS,
         old="                rc = do_close(ld, getStream(rs), force) && rc\n",
         new="                rc = rc && true\n"),
    dict(id="LD4-7 closing a pair closes the read half only (KILL: d112, d126)", file=F, targets=TS,
         old="                rc = do_close(ld, getStream(ws), force)\n",
         new="                rc = true\n"),
    dict(id="LD4-8 a closed half of a pair is closed again (KILL: d124, d125: the second close raises)", file=F, targets=TS,
         old="            if ws !== nothing && !ws.erased\n                rc = do_close(ld, getStream(ws), force)\n",
         new="            if ws !== nothing\n                rc = do_close(ld, getStream(ws), force)\n"),
    dict(id="LD4-9 stream_pair/3 of a pair unifies the read stream with the third argument (KILL: d110, d121)", file=F, targets=TL,
         old="                rc = rc && PL_unify_stream_or_alias(ld, A2, rs)\n",
         new="                rc = rc && PL_unify_stream_or_alias(ld, A3, rs)\n"),
    dict(id="LD4-10 stream_pair/3 of a pair leaves the third argument alone (KILL: d110, d121)", file=F, targets=TL,
         old="                rc = rc && PL_unify_stream_or_alias(ld, A3, ws)\n",
         new="                rc = rc && true\n"),
    dict(id="LD4-11 a single stream split by stream_pair/3 goes to the wrong side (KILL: d115, d116)", file=F, targets=TL,
         old="                    rc = if (s.flags & SIO_INPUT) != 0\n",
         new="                    rc = if (s.flags & SIO_INPUT) == 0\n"),
    dict(id="LD4-12 stream_pair/3 builds the pair with the sides swapped (KILL: d111, d112)", file=F, targets=TL,
         old="    pair = stream_ref(getStreamContext(gd, in), getStreamContext(gd, out))\n",
         new="    pair = stream_ref(getStreamContext(gd, out), getStreamContext(gd, in))\n"),
    dict(id="LD4-13 a non-stream argument of stream_pair/3 is a domain error (KILL: d113 is existence_error first; this one raises nothing new where the lookup already raised: see equivalent)", file=F, targets=TL,
         equivalent="read, not run: PL_error does not overrule the pending existence_error(stream, foo) that get_stream_handle(SH_ERRORS) raised (src/pl-error.jl PL_error: an exception already pending is not overruled); the type is only observable for an atom that names an open stream-less alias, which swipl's lookup also refuses first",
         old='            rc = PL_error(ld, "", 0, "", ERR_TYPE, mk_sym(T, :stream_pair), A1)\n',
         new='            rc = PL_error(ld, "", 0, "", ERR_TYPE, mk_sym(T, :stream), A1)\n'),
    dict(id="LD4-14 getStreamWithPosition without SH_NOPAIR reads a pair silently (KILL: d118)", file=F, targets=TL,
         old="    s = term_stream_handle(ld, stream, SH_ERRORS | SH_NOPAIR)\n",
         new="    s = term_stream_handle(ld, stream, SH_ERRORS)\n"),
    dict(id="LD4-15 the registration of stream_pair/3 is gone (KILL: every row of d109-d127)", file=F, targets=TL,
         old='    PL_extension("stream_pair", 3, pl_stream_pair3_va, PL_FA_VARARGS),\n',
         new=""),
]
