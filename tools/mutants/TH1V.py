# ORIGINAL: the TH1 VM-yield mutant list — no swipl-devel counterpart.
# tools/mutants/TH1V.py — the mutation battery of the VM yield of TH1 (pl-vmi.c:2410-2448 I_YIELD, pl-wam.c:3874-3905 the resume in
# PL_next_solution, pl-wam.c:3254-3260 PL_can_yield, pl-wam.c:3331 PL_yielded, pl-wam.c PL_open_query's `yield.term = 0`, pl-thread.c:4363-4366
# the YIELD_ENGINE_YIELD case of interactor_post_answer_nolock): src/pl-wam.jl and src/pl-thread.jl. Run ONCE, in CI
# (.github/workflows/mutation.yml; locally one mutant under debug is fine, no local list: D-0220). Format: tools/mutate_drive.py's (as
# TH1E.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# KILL: test/core_lang/test_engine_yield_swipl.jl (rows ey01-ey16, eyk1, the white-box testsets); the KILL lists are what the rows are
# EXPECTED to do (read, not run): the battery's verdict is the evidence. Written by a coding agent with NO Julia process: every `old` was
# counted exactly once with a throwaway `python3 -I` script (a text count); RE-FIT any `old` that `tools/warm.sh fmt` rewrapped.
# TARGETS (audit D-0238): the I_YIELD instruction is run by the engine rows (test_engine_yield_swipl.jl, test_engines_swipl.jl: yl1, yl2) and by
# the non-engine branch (the permission error) of test_cont_run_swipl.jl (r_yield_out) and test_cont_boot_swipl.jl (c_yield); the resume and
# PL_open_query's init are reached by every query of every file, but a mutant there that only those four files see is killed by them first.
# STALE COMMENT, NOT A STALE MUTANT: CONT1-V2 (tools/mutants/CONT1.py, `PL_Q_ALLOW_YIELD) == 0` -> `!= 0`) says "the engine branch refuses by
# name instead"; since the VM yield a query without the flag yields instead of raising: the mutant is still killed (r_yield_out, c_yield).
# MAY SURVIVE (no row is expected to kill it; the battery decides, then a row or the reason): TH1V-V3 (the yield foreign frame is not closed
# at the resume: the later close of the outer frame restores `fli_context` all the same, a leak of a few cells until the frame exits) and TH1V-V5
# (the second @SAVE_REGISTERS: ARGP is not read by the instructions that follow I_YIELD, I_EXIT and I_DEPART).
W = "src/pl-wam.jl"
T = "src/pl-thread.jl"
TARGETS = [
    "test/core_lang/test_engine_yield_swipl.jl",
    "test/core_lang/test_engines_swipl.jl",
    "test/core_lang/test_cont_run_swipl.jl",
    "test/core_lang/test_cont_boot_swipl.jl",
]
MUTANTS = [
    # ---- the resume in PL_next_solution
    dict(id="TH1V-V1 a query resumes when it has NOT yielded (KILL every query: the first call runs the resume branch; ey01, yl1)",
         file=W, targets=TARGETS,
         old="    if q.yield_term != 0                            # resume after yield\n",
         new="    if q.yield_term == 0                            # resume after yield\n"),
    dict(id="TH1V-V2 the resume does not clear yield_term: the next call resumes again (KILL ey01 4th answer, ey09, the white-box `q.yield_term == 0`)",
         file=W, targets=TARGETS,
         old="        q.yield_term = 0                            # QF->yield.term = 0\n        fid = q.foreign_frame\n",
         new="        fid = q.foreign_frame\n"),
    dict(id="TH1V-V3 the resume does not close the yield foreign frame (MAY SURVIVE, see the header: a leak of cells, the outer close restores fli_context)",
         file=W, targets=TARGETS,
         old="        q.foreign_frame = 0\n        PL_close_foreign_frame(ld, fid)\n        @LOAD_REGISTERS(QID)\n",
         new="        q.foreign_frame = 0\n        @LOAD_REGISTERS(QID)\n"),
    # ---- I_YIELD
    dict(id="TH1V-V4 lTop is lowered under a younger choice point instead of kept (KILL ey07, ey01: findall and member leave a choice point younger than the frame)",
         file=W, targets=TARGETS,
         old="if ld.BFR == 0 || ld.choices[ld.BFR].base < ld.frames[FR].base",
         new="if ld.BFR == 0 || ld.choices[ld.BFR].base > ld.frames[FR].base"),
    dict(id="TH1V-V5 the registers are not saved again after ARGP changed (MAY SURVIVE, see the header)",
         file=W, targets=TARGETS,
         old="    ARGP = argp_t{T}(ARGP_SLOT, argFrameP(ld.lTop, 0), ph)             # ARGP = argFrameP(lTop, 0)\n    @SAVE_REGISTERS(QID)\n",
         new="    ARGP = argp_t{T}(ARGP_SLOT, argFrameP(ld.lTop, 0), ph)             # ARGP = argFrameP(lTop, 0)\n"),
    dict(id="TH1V-V6 yield.term links argument 2 (the code), not argument 1 (KILL ey01, ey04, the white-box f(_) and g(1))",
         file=W, targets=TARGETS,
         old="_slot_link!(ld, iy_q.yield_term + 1, argFrameP(ld.frames[FR].base, 0) + 1)",
         new="_slot_link!(ld, iy_q.yield_term + 1, argFrameP(ld.frames[FR].base, 1) + 1)"),
    dict(id="TH1V-V7 the yield code returned is code + 1 (KILL the white-box 300 and 256, every yield row: engine_next reads 257 as an unknown code)",
         file=W, targets=TARGETS,
         old="        return iy_code                              # SOLUTION_RETURN((int)code)\n",
         new="        return iy_code + 1                          # SOLUTION_RETURN((int)code)\n"),
    dict(id="TH1V-V8 the type-error branch does not reset yield_term: a caught error leaves a stale yield (KILL eyk1, the kernel-only row of the named DIVERGES)",
         file=W, targets=TARGETS,
         old="        iy_q.foreign_frame = 0\n        iy_q.yield_term = 0\n        PL_close_foreign_frame(ld, iy_fid)\n",
         new="        iy_q.foreign_frame = 0\n        PL_close_foreign_frame(ld, iy_fid)\n"),
    dict(id="TH1V-V12 the type error names `atom`, not `integer` (KILL ey10)",
         file=W, targets=TARGETS,
         old="PL_error(ld, ERR_TYPE, mk_sym(T, :integer), iy_t)",
         new="PL_error(ld, ERR_TYPE, mk_sym(T, :atom), iy_t)"),
    # ---- PL_can_yield, PL_yielded, PL_open_query
    dict(id="TH1V-V9 PL_can_yield is true for a query WITHOUT the flag (KILL the white-box testsets: true after opening with ALLOW_YIELD is false, false for the plain query is true)",
         file=W, targets=TARGETS,
         old="(ld.queries[ld.query].flags & PL_Q_ALLOW_YIELD) != 0",
         new="(ld.queries[ld.query].flags & PL_Q_ALLOW_YIELD) == 0"),
    dict(id="TH1V-V10 PL_yielded returns the foreign frame, not the term reference (KILL the white-box `q.yield_term == t`, every yield row: the engine records the wrong term)",
         file=W, targets=TARGETS,
         old="    return qf.yield_term                            # return qf->yield.term\n",
         new="    return qf.foreign_frame                         # return qf->yield.term\n"),
    dict(id="TH1V-V11 PL_open_query does not reset yield_term: a pool record reused after a yielded query reads as a resume (KILL the white-box 'a yielded query is closed' testset: `q2.yield_term == 0`)",
         file=W, targets=TARGETS,
         old="    q.yield_term = 0                            # qf->yield.term = 0\n",
         new=""),
    # ---- the YIELD_ENGINE_YIELD case of interactor_post_answer_nolock
    dict(id="TH1V-V13 the yield answer is the engine's template, not the yielded term (KILL ey01, ey02, ey04, ey06, ey13, yl1)",
         file=T, targets=TARGETS,
         old="        r = PL_record(eld, PL_yielded(eld, q))",
         new="        r = PL_record(eld, th.interactor_argv)"),
    dict(id="TH1V-V14 the yield code is not recognised: the default branch raises domain_error(engine_yield_code, 256) (KILL ey01, yl1)",
         file=T, targets=TARGETS,
         old="    elseif rc == YIELD_ENGINE_YIELD                 # engine_yield/1\n",
         new="    elseif rc == YIELD_ENGINE_YIELD + 1             # engine_yield/1\n"),
]
