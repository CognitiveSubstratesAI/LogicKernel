# ORIGINAL: LB5's mutant list — no swipl-devel counterpart.
# tools/mutants/LB5.py — the mutation battery of LB5 (pl-file.c: set_stream/2 alias(Std) -> setStandardStream, current_io
# (current_input/1, current_output/1), getStreamWithPosition (line_count/2, line_position/2), tab, at_end_of_stream, get_code2,
# put_code; pl-arith.c PL_eval_expression_to_int64_ex; pl-write.c write_size/4 with write_length_options; pl-option.c get_optval's
# OPT_INT64), run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's
# (as MOD3b.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`. Killed by
# test/core_lang/test_lb5_swipl.jl (rows lb001-lb110 named in each id's KILL). Verdicts: written by the battery, not yet run.
# The `old` strings are written in the repo's formatted style BEFORE `tools/warm.sh fmt` ran (the coding agent had no daemon):
# RE-FIT any that fmt rewraps (mutate_drive.py refuses a string that does not occur exactly once). Every `old` was checked to
# occur exactly once in the source at wip/lb5 (a text count, no Julia).
# EQUIVALENT (declared, each with its code reason):
#   * LB5-X1, LB5-X2: write_size's `clearPrologFlagMask!(ld, PLFLAG_ISO)` (src/pl-write.jl:2514) and the restore
#     `ld.prolog_flag_mask = oldmask` (:2517). The only reader of the ISO flag on the path write_size runs is PL_scan_options'
#     arity-0 option test (src/os/pl-option.jl:120: a bare option atom such as `quoted` is accepted only when the flag is clear),
#     the flag's default is false (src/os/pl-prologflag.jl:1873) and no row of any target file sets it, so clearing it is a
#     no-op and not restoring it restores the same value. A row `set_prolog_flag(iso, true)` followed by a bare-atom option would
#     tell the mutants apart; swipl's own answer for that row is not pinned (left out of this step).
# NOT LISTED (each with its reason):
#   * getStreamWithPosition's `if s.position === nothing` -> permission_error(property, position, S) (src/os/pl-file.jl): no
#     oracle row reaches it. swipl 10.1.19 answers ok-1 / ok-0 for line_count / line_position of
#     open(..., [record_position(false)]) (rows lb010, lb011 pin that), so no swipl-compared row has a stream that raises the
#     upstream permission_error; lb010-lb011 are not mutant killers and no mutant of the branch is listed (D-0238: a survivor
#     there would prove nothing about the branch).
#   * tab's `count === nothing && return false` (src/os/pl-file.jl): dropping it makes the next line compare `nothing > 0`, a
#     MethodError thrown by Julia, not a Prolog verdict.
# TARGETS (audit D-0238): each mutant lists every test file that exercises its mutated code; the step's own file first (a run
# stops at the first target that decides). grep -l over test/ for the predicate names gave the lists below; line_count/2 in
# test_nth_clause_swipl.jl, test_declare_destroy_swipl.jl, test_module_swipl.jl and test_pr1_swipl.jl is a clause, module or
# predicate PROPERTY name, not the stream predicate, so those files are left out. PL_eval_expression_to_int64_ex (tab's only
# caller, src/os/pl-file.jl:1642), write_size and OPT_INT64 (write_size's options, src/pl-write.jl:2475) are reached by
# test_lb5_swipl.jl alone. Every TARGETS file holds @test / @testset (grep -L found no helper).
LB5T = ["test/core_lang/test_lb5_swipl.jl"]
WF = "test/core_text/test_write_family_swipl.jl"
CR = "test/core_text/test_canonical_readatom_swipl.jl"
S2A = "test/core_lang/test_s2a_swipl.jl"
OC = "test/files/test_open_close_swipl.jl"
IO = "test/core_text/test_io.jl"
BRIEF = [WF, CR, S2A, OC]
PF = LB5T + BRIEF
CUR = LB5T + [IO, WF, CR, S2A, OC, "test/core_lang/test_compare_swipl.jl", "test/core_lang/test_blob.jl"]
CURIN = CUR + ["test/files/test_qlf_swipl.jl"]
POS = LB5T + [IO, "test/files/test_stream_swipl.jl", S2A, WF, CR, OC]
SETS = LB5T + [S2A, IO, WF, CR, OC]
PUT = PF + ["test/core_text/test_read.jl"]
TARGETS = [
    "test/core_lang/test_lb5_swipl.jl",
    "test/core_text/test_io.jl",
    "test/core_text/test_write_family_swipl.jl",
    "test/core_text/test_canonical_readatom_swipl.jl",
    "test/core_text/test_read.jl",
    "test/core_lang/test_s2a_swipl.jl",
    "test/core_lang/test_compare_swipl.jl",
    "test/core_lang/test_blob.jl",
    "test/files/test_open_close_swipl.jl",
    "test/files/test_stream_swipl.jl",
    "test/files/test_qlf_swipl.jl",
]   # the baseline's (mutate_ci.py plan reads TARGETS): the union of the lists above
F = "src/os/pl-file.jl"
A = "src/pl-arith.jl"
W = "src/pl-write.jl"
O = "src/os/pl-option.jl"
MUTANTS = [
    # ── pl-file.c set_stream/2 alias(Std) ──
    dict(id="LB5-A1 set_stream alias(Std) of a standard name does not install the stream (KILL lb097, lb098, lb099)",
         file=F, targets=SETS,
         old="            setStandardStream(ld, i, s)\n",
         new="            nothing\n"),
    # ── pl-file.c current_io ──
    dict(id="LB5-B1 current_io compares a bound stream with the others: `s !== cur` (KILL lb020, lb021)",
         file=F, targets=CUR,
         old="        return s === cur\n",
         new="        return s !== cur\n"),
    dict(id="LB5-B2 current_io takes a non-stream (foo, 1) without the domain error (KILL lb017, lb018, lb019)",
         file=F, targets=CUR,
         old="        is_stream_blob(ld, t) || return not_a_stream(ld, t, 0)\n",
         new="        nothing\n"),
    dict(id="LB5-B3 current_input/1 answers the current OUTPUT (KILL lb015, lb021)",
         file=F, targets=CURIN,
         old="Scurin(ld), :current_input)",
         new="Scurout(ld), :current_input)"),
    # ── pl-file.c getStreamWithPosition, line_count, line_position ──
    dict(id="LB5-C1 line_count answers the column (KILL lb001, lb002, lb004, lb005)", file=F, targets=POS,
         old="    n = (s.position::IOPOS).lineno\n",
         new="    n = (s.position::IOPOS).linepos\n"),
    dict(id="LB5-C2 line_position answers the line number (KILL lb001, lb002, lb035)", file=F, targets=POS,
         old="    n = (s.position::IOPOS).linepos\n",
         new="    n = (s.position::IOPOS).lineno\n"),
    dict(id="LB5-C3 getStreamWithPosition takes SH_ALIAS (PL_get_stream passes flags 0): a non-atom is domain_error(stream_or_alias, X) (KILL lb109, lb110)",
         file=F, targets=POS,
         old="stream, SH_ERRORS)\n    s === nothing && return nothing\n    if s.position",
         new="stream, SH_ERRORS | SH_ALIAS)\n    s === nothing && return nothing\n    if s.position"),
    # ── pl-file.c tab ──
    dict(id="LB5-D1 tab writes one space too many: `count >= 0` (KILL lb022-lb024, lb029, lb030, lb032, lb035)",
         file=F, targets=PF,
         old="    while count > 0\n",
         new="    while count >= 0\n"),
    # ── pl-file.c at_end_of_stream ──
    dict(id="LB5-E1 at_end_of_stream treats a buffered stream as unbuffered: `rval > 0` (KILL lb036, lb038, lb039)",
         file=F, targets=PF,
         old="    if rval < 0\n",
         new="    if rval > 0\n"),
    # ── pl-file.c get_code2, put_code ──
    dict(id="LB5-F1 get_code(S, end_of_file) raises the type error: the end_of_file test is dropped (KILL lb050)",
         file=F, targets=PF,
         old="        (i == -1 || (a !== nothing && sym_key(a) == sym_key(mk_sym(T, :end_of_file)))) &&\n",
         new="        false &&\n"),
    dict(id="LB5-F2 put_code writes nothing (KILL lb057, lb064, lb065, lb067, lb071, lb073)", file=F, targets=PUT,
         old="    Sputcode(c, s)\n",
         new="    nothing\n"),
    # ── pl-arith.c PL_eval_expression_to_int64_ex ──
    dict(id="LB5-G1 tab(2.5): a float is taken as an integer expression (KILL lb028, lb029)", file=A, targets=LB5T,
         old="        if toIntegerNumber(ld, n, 0)\n",
         new="        if true\n"),
    dict(id="LB5-G2 tab(1<<70): a value past 64 bits is taken as fitting (KILL lb031)", file=A, targets=LB5T,
         old="                if fits\n",
         new="                if true\n"),
    # ── pl-write.c write_size ──
    dict(id="LB5-H1 write_size: the empty text has height 1 (KILL lb077, lb078)", file=W, targets=LB5T,
         old="    height = (width > 0 || pos.lineno > 0) ? pos.lineno + 1 : 0\n",
         new="    height = pos.lineno + 1\n"),
    dict(id="LB5-H2 write_size: a width equal to max_width fails (KILL lb080, lb092)", file=W, targets=LB5T,
         old="    (width > max_width || height > max_height) && return false\n",
         new="    (width >= max_width || height > max_height) && return false\n"),
    dict(id="LB5-H3 write_size: the width is the last line's, not the widest (KILL lb107)", file=W, targets=LB5T,
         old="            pos.linepos > width && (width = pos.linepos)\n",
         new="            width = pos.linepos\n"),
    dict(id="LB5-H4 write_size leaves the memory stream as the current output (KILL lb094)", file=W, targets=LB5T,
         old="        toldString(ld)\n",
         new="        nothing\n"),
    dict(id="LB5-X1 write_size keeps the ISO flag set while writing (EQUIVALENT: src/pl-write.jl:2514, see the header)",
         file=W, targets=LB5T,
         equivalent="src/pl-write.jl:2514 — the ISO flag defaults to false (pl-prologflag.jl:1873) and is read on this path only by "
                    "PL_scan_options' bare-atom test (pl-option.jl:120); no target row sets it",
         old="        clearPrologFlagMask!(ld, PLFLAG_ISO)\n",
         new="        nothing\n"),
    dict(id="LB5-X2 write_size does not restore the flag mask (EQUIVALENT: src/pl-write.jl:2517, see the header)",
         file=W, targets=LB5T,
         equivalent="src/pl-write.jl:2517 — without the clear (LB5-X1) the mask is unchanged, so restoring it is a no-op",
         old="        ld.prolog_flag_mask = oldmask\n",
         new="        nothing\n"),
    # ── pl-option.c get_optval OPT_INT64 ──
    dict(id="LB5-I1 OPT_INT64 reads every limit as 0 (KILL lb080, lb082, lb092, lb093)",
         file=O, targets=LB5T,
         old="        i = PL_get_int64_ex(ld, val)\n",
         new="        i = 0\n"),
]
