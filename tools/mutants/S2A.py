# ORIGINAL: S2a's mutant list — no swipl-devel counterpart.
# tools/mutants/S2A.py — the mutation battery of S2a (os/pl-file.c stream predicates the boot files call: prompt/2, prompt1/1,
# the input context trio, flush_output/1, is_stream/1, '$alias_stream'/2, get_char/2, peek_char/2, skip/2, '$stream_property'/2,
# '$stream_properties'/2, '$streams_properties'/2, set_stream/2; pl-stream.c Ssetbuffer, Ssetenc), run ONCE, in CI
# (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as MOD3b.py): `id`, `file`,
# `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`. Killed by test/core_lang/test_s2a_swipl.jl (rows
# s001-s137 named in each id's KILL). Verdicts: written by the battery, not yet run.
# The `old` strings are written in the repo's formatted style BEFORE `tools/warm.sh fmt` ran (the coding agent had no daemon):
# RE-FIT any that fmt rewraps (mutate_drive.py refuses a string that does not occur exactly once). Every `old` was checked to
# occur exactly once in the source at wip/s2a (a text count, no Julia).
# NOT LISTED (each with its reason):
#   * prompt1's `ld.prompt_first_used = false`: EQUIVALENT in the rows, read not run — the flag is read by the reader's prompt
#     choice (a later step), no predicate shows it.
#   * pl_set_stream2_va's stream-pair test (`SS_NOPAIR` branch, symbol_stream_pair_not_allowed): no pair stream exists yet, no
#     row reaches it (left to the step that makes stream_pair/3).
# TARGETS (audit D-0238): the step's own file first (a run stops at the first target that decides); the stream files that reach
# pl-file.jl's handles, open/close and the stream layer (test/files/test_open_close_swipl.jl, test/files/test_stream_swipl.jl)
# are listed where the mutated code is shared with them (get_stream_handle users, Ssetenc, S__setbuf).
TS = ["test/core_lang/test_s2a_swipl.jl"]
TF = ["test/files/test_open_close_swipl.jl", "test/files/test_stream_swipl.jl"]
ALL = TS + TF
TARGETS = ALL                                        # the baseline's targets (mutate_ci.py plan reads TARGETS; pre-push check 5)
F = "src/os/pl-file.jl"
S = "src/os/pl-stream.jl"
MUTANTS = [
    # ── prompt/2, prompt1/1 ──
    dict(id="S2A-P1 prompt/2 keeps the old prompt when the first argument does not unify: it still sets the new one (KILL s005)",
         file=F, targets=TS,
         old="    PL_unify_atom(ld, A1, ld.prompt_current) || return FFALSE\n",
         new="    PL_unify_atom(ld, A1, ld.prompt_current)\n"),
    dict(id="S2A-P2 prompt/2 never stores the new prompt (KILL s001, s006)", file=F, targets=TS,
         old="    ld.prompt_current = a\n",
         new="    nothing\n"),
    dict(id="S2A-P3 prompt1/1 reads only an atom, not a string or number (KILL s008, s009)", file=F, targets=TS,
         old="        txt = PL_get_text(ld, A1, CVT_ALL | CVT_EXCEPTION)\n        txt === nothing && return FFALSE\n        PL_canonicalise_text(txt) == 1",
         new="        txt = PL_get_text(ld, A1, CVT_ATOM | CVT_EXCEPTION)\n        txt === nothing && return FFALSE\n        PL_canonicalise_text(txt) == 1"),
    # ── '$push_input_context'/1, '$pop_input_context'/0, '$input_context'/1 ──
    dict(id="S2A-I1 $pop_input_context leaves the context on the stack (KILL s012)", file=F, targets=TS,
         old="        c = pop!(ld.input_context_stack)",
         new="        c = ld.input_context_stack[end]"),
    dict(id="S2A-I2 $input_context lists the oldest context first (KILL s014)", file=F, targets=TS,
         old="    for c in Iterators.reverse(ld.input_context_stack)\n",
         new="    for c in ld.input_context_stack\n"),
    dict(id="S2A-I3 $input_context answers the functor input/4 with the wrong type tag (KILL s013, s014)", file=F, targets=TS,
         old="PL_unify_atom(ld, arg, c.type) &&",
         new="PL_unify_atom(ld, arg, mk_sym(T, :input)) &&"),
    # ── is_stream/1, '$alias_stream'/2, flush_output/1 ──
    dict(id="S2A-F1 is_stream/1 answers the opposite for a live stream (KILL s026, s030, s031)", file=F, targets=TS,
         old="    return get_stream_handle(ld, a, SH_UNLOCKED) === nothing ? FFALSE : FTRUE\n",
         new="    return get_stream_handle(ld, a, SH_UNLOCKED) === nothing ? FTRUE : FFALSE\n"),
    dict(id="S2A-F2 is_stream/1 holds for a non-atom (KILL s028, s029)", file=F, targets=TS,
         old="    a = PL_get_atom(ld, PL__t0)\n    a === nothing && return FFALSE\n    return get_stream_handle(ld, a, SH_UNLOCKED)",
         new="    a = PL_get_atom(ld, PL__t0)\n    a === nothing && return FTRUE\n    return get_stream_handle(ld, a, SH_UNLOCKED)"),
    dict(id="S2A-F3 $alias_stream/2 does not unify the stream with its second argument (KILL s032, s036)", file=F, targets=TS,
         old="    s.context != 0 || return FFALSE\n    return unify_stream_ref(ld, A2, s) ? FTRUE : FFALSE\n",
         new="    s.context != 0 || return FFALSE\n    return FTRUE\n"),
    dict(id="S2A-F4 flush_output/1 skips the stream's error status (KILL s021)", file=F, targets=TS,
         old="        Sflush(s)\n        return streamStatus(ld, s)\n",
         new="        Sflush(s)\n        return true\n"),
    # ── get_char/2, peek_char/2, skip/2 ──
    dict(id="S2A-C1 skip/2 stops at the end of the file only: it never stops at the code (KILL s040, s041)", file=F, targets=TS,
         old="        (r == c || r == EOF) && break\n",
         new="        r == EOF && break\n"),
    dict(id="S2A-C2 peek_char/2 consumes the character (KILL s038, s058, s059)", file=F, targets=TS,
         old="    c = Speekcode(s)\n",
         new="    c = Sgetcode(s)\n"),
    dict(id="S2A-C3 get_char/2 raises no type error for a non-character (KILL s047)", file=F, targets=TS,
         old="        PL_unify_atom(ld, chr, codeToAtom(T, c)) && return true     # (c == -1: ATOM_end_of_file)\n\n        PL_get_char(ld, chr)                        # set type-error\n",
         new="        PL_unify_atom(ld, chr, codeToAtom(T, c)) && return true     # (c == -1: ATOM_end_of_file)\n\n        nothing\n"),
    dict(id="S2A-C4 get_char/2 skips the stream's error status: no past-end error (KILL s044)", file=F, targets=TS,
         old="        streamStatus(ld, s) || return false         # I/O error\n\n        PL_unify_atom(ld, chr, codeToAtom(T, c))",
         new="        nothing\n\n        PL_unify_atom(ld, chr, codeToAtom(T, c))"),
    dict(id="S2A-C5 PL_unify_char answers a code, not a char, for an unbound argument (KILL s038, s039, s040)", file=F, targets=TS,
         old="        how === :char && return PL_unify_atom(ld, chr, codeToAtom(T, c))\n",
         new="        how === :char && return PL_unify_integer(ld, chr, c)\n"),
    # ── '$stream_property'/2, '$stream_properties'/2, '$streams_properties'/2 ──
    dict(id="S2A-Q1 mode(M) of a readable stream is write (KILL s061, s063, s080)", file=F, targets=ALL,
         old="        mode = :read\n",
         new="        mode = :write\n"),
    dict(id="S2A-Q2 position/1 swaps line and line position (KILL s058, s059, s075, s109)", file=F, targets=TS,
         old="_PL_get_arg(ld, 2, prop, a) && PL_unify_int64(ld, a, pos.lineno) &&",
         new="_PL_get_arg(ld, 2, prop, a) && PL_unify_int64(ld, a, pos.linepos) &&"),
    dict(id="S2A-Q3 end_of_stream(at) is reported as not (KILL s060)", file=F, targets=TS,
         old="            val = :at\n",
         new="            val = :not\n"),
    dict(id="S2A-Q4 eof_action(reset) is reported as eof_code (KILL s099)", file=F, targets=TS,
         old="        val = :reset\n",
         new="        val = :eof_code\n"),
    dict(id="S2A-Q5 file_name/1 is answered for a stream without a context only (KILL s068, s112, s113)", file=F, targets=TS,
         old="    if s.magic == SIO_MAGIC && s.context != 0\n        name = fileNameStream(",
         new="    if s.magic == SIO_MAGIC && s.context == 0\n        name = fileNameStream("),
    dict(id="S2A-Q6 $stream_property/2 raises no error for a bad stream (KILL s085, s086)", file=F, targets=TS,
         old="    p === nothing && return FFALSE\n    s = term_stream_handle(ld, A1, SH_ERRORS | SH_UNLOCKED)\n    s === nothing && return FFALSE\n    a1 = PL_new_term_ref(ld)\n    p.arity == 0",
         new="    p === nothing && return FFALSE\n    s = term_stream_handle(ld, A1, SH_UNLOCKED)\n    s === nothing && return FFALSE\n    a1 = PL_new_term_ref(ld)\n    p.arity == 0"),
    dict(id="S2A-Q7 $stream_properties/2 lists the properties in reverse order (KILL s080)", file=F, targets=TS,
         old="    rc = true\n\n    for p in sprop_list\n",
         new="    rc = true\n\n    for p in reverse(sprop_list)\n"),
    dict(id="S2A-Q8 $streams_properties/2 does not test the pair against the property: every stream is listed (KILL s083, s081)",
         file=F, targets=TS,
         old="                can_unify_cells(ld, -(A1 + 1), -(pt + 1), ex) &&\n",
         new="                true &&\n"),
    # ── set_stream/2, pl-stream.c Ssetbuffer, Ssetenc ──
    dict(id="S2A-T1 set_stream/2 buffer_size accepts 0 (KILL s097)", file=F, targets=TS,
         old="        size < 1 && return PL_error(",
         new="        size < 0 && return PL_error("),
    dict(id="S2A-T2 set_stream/2 type(text) clears the text flag it sets (KILL s103)", file=F, targets=ALL,
         old="            s.flags |= SIO_TEXT\n        elseif _sym_is(type, :binary)\n",
         new="            s.flags &= ~SIO_TEXT\n        elseif _sym_is(type, :binary)\n"),
    dict(id="S2A-T3 set_stream/2 close_on_abort(false) clears the no-close flag (KILL s105)", file=F, targets=TS,
         old="            s.flags &= ~SIO_NOCLOSE\n        else\n            s.flags |= SIO_NOCLOSE\n",
         new="            s.flags |= SIO_NOCLOSE\n        else\n            s.flags &= ~SIO_NOCLOSE\n"),
    dict(id="S2A-T4 set_stream/2 record_position(false) keeps the position (KILL s107, s108)", file=F, targets=TS,
         old="            s.position = nothing\n",
         new="            nothing\n"),
    dict(id="S2A-T5 set_stream/2 line_position(N) stores no position (KILL s109)", file=F, targets=TS,
         old="            pos.linepos = lpos\n",
         new="            nothing\n"),
    dict(id="S2A-T6 set_stream/2 file_name(F) keeps the old name (KILL s112, s113)", file=F, targets=TS,
         old="        setFileNameStream(gd, s, mk_sym(T, Symbol(text_string(txt))))\n",
         new="        nothing\n"),
    dict(id="S2A-T7 set_stream/2 timeout(infinite) is refused like any other time (KILL s136)", file=F, targets=TS,
         old="        v !== nothing && _sym_is(v, :infinite) && return true",
         new="        v !== nothing && _sym_is(v, :never_infinite) && return true"),
    dict(id="S2A-T8 set_stream/2 alias(A) names no stream (KILL s089, s036, s037)", file=F, targets=ALL,
         old="        aliasStream(gd, s, alias)\n        return true\n",
         new="        return true\n"),
    dict(id="S2A-T9 set_stream/2 newline(dos) sets the posix mode (KILL s127)", file=F, targets=TS,
         old="        s.newline = mode & 0x3\n",
         new="        s.newline = 0\n"),
    dict(id="S2A-T10 set_stream/2 write_errors(ignore) clears the flag (KILL s125)", file=F, targets=TS,
         old="            s.flags |= SIO_NOERROR\n",
         new="            s.flags &= ~SIO_NOERROR\n"),
    dict(id="S2A-T11 set_stream/2 representation_errors(xml) sets the prolog mode (KILL s122)", file=F, targets=TS,
         old="            s.flags |= SIO_REPXML\n",
         new="            s.flags |= SIO_REPPL\n"),
    dict(id="S2A-T12 the table gives eof_action to the output side: an input stream is never set (KILL s099)", file=F, targets=TS,
         old="    (:eof_action, SS_READ),\n",
         new="    (:eof_action, SS_WRITE),\n"),
    dict(id="S2A-T13 Ssetenc keeps the text flag after an octet encoding (KILL s116)", file=S, targets=ALL,
         old="        s.flags &= ~SIO_TEXT\n    else\n        s.flags |= SIO_TEXT\n    end\n    return 0\n",
         new="        nothing\n    else\n        s.flags |= SIO_TEXT\n    end\n    return 0\n"),
    dict(id="S2A-T14 Ssetbuffer keeps the user-buffer mark: a no-op for the one caller, which passes no buffer (KILL none)",
         file=S, targets=ALL,
         equivalent="src/os/pl-stream.jl:S__setbuf — read, not run: set_stream/2 calls `Ssetbuffer(s, nothing, size)`, and `S__setbuf` with `buffer === nothing` already clears SIO_USERBUF (`newflags &= ~SIO_USERBUF`), so the mark is clear before and after",
         old="    S__setbuf(s, buffer, size) != -1 && (s.flags &= ~SIO_USERBUF)\n",
         new="    S__setbuf(s, buffer, size)\n"),
]
