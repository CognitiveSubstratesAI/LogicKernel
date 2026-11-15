# ORIGINAL: ASSERT-GEN's mutant list — no swipl-devel counterpart.
# tools/mutants/AGEN.py — the mutation battery of ASSERT-GEN (audit D-0713 (3)): clause/2 (src/pl-comp.jl clause_ndet) and retract/1
# (src/pl-proc.jl pl_retract1_va) store the predicate access object's generation in the frame (`setGenerationFrameVal(environment_frame,
# dref->generation)`, pl-comp.c:7413 and pl-proc.c:3180 at swipl-devel 18168e62) and no longer assert that it equals the generation the frame took
# at the call. The format is tools/mutate_drive.py's: `id`, `file`, `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# TARGETS (D-0238): every test file that runs the mutated code: the new rows (test_generation_swipl.jl) and the retract/1 and clause/2 files of NF2.
# Each `old` was counted by a python scan of this tree (once per file). Written BEFORE `tools/warm.sh fmt` ran on the tree: re-check after it.
TG = ["test/core_lang/test_generation_swipl.jl"]
TR = ["test/db/test_retract_swipl.jl"]
TC = ["test/db/test_clause_swipl.jl"]
TARGETS = TG + TR + TC                                  # the baseline's targets (mutate_ci.py plan reads TARGETS)
P = "src/pl-proc.jl"
C = "src/pl-comp.jl"

STORE_C = '''        ld.frames[fr].generation = dref.generation          # setGenerationFrameVal(environment_frame, dref->generation)
'''
STORE_R = '''        ld.frames[fr].generation = dref.generation      # setGenerationFrameVal(environment_frame, dref->generation)
'''
MUTANTS = [
    # ---- the removed assert reinstated: it raises on clause/2 of a predicate declared autoload/2 (a12-a19), killed by the non-throwing rows
    dict(id="AGEN-C1 clause/2 asserts the access object's generation equals the frame's", file=C, targets=TG,
         old=STORE_C,
         new='''        @assert dref.generation == generationFrame(ld.frames[fr])
''' + STORE_C),
    # the retract/1 form: no trigger exists in the kernel today (nothing between the call and the access object creates a generation; the
    # wakeup rows b1-b13 and the erase-listener rows c1-c4 all run before or after, never between), so this mutant is EQUIVALENT
    dict(id="AGEN-R1 retract/1 asserts the access object's generation equals the frame's", file=P, targets=TG + TR,
         old=STORE_R,
         new='''        @assert dref.generation == generationFrame(ld.frames[fr])
''' + STORE_R,
         equivalent="src/pl-proc.jl pl_retract1_va: between the call (setGenerationFrame, pl-wam.jl) and pushPredicateAccessObj! run only "
                    "get_head_and_body_clause, get_head_functor, isCurrentProcedure and the flag tests, and none of them creates a generation "
                    "(a wakeup runs before the call or after the exit: rows p1b1-p1b13); the assert never fires"),
    # ---- the frame keeps the generation it took at the call instead of the access object's: killed where trapUndefined loaded a library
    # in between: the autoload hook of rows p1e1-p1e6 asserts the pe/1 clauses there, so the frame (the call's generation) would not see them and the
# answers would be `[]`. The rows p1a12-p1a19 (library(lists) loaded there) and p1d1-p1d10 (the redo's view, in the generation the call took) were
# found NOT to kill this mutant by the hand check at e40b41bb (audit D-0758 (2)); p1e* is not yet run on the kernel (written without Julia)
    dict(id="AGEN-C2 clause/2 keeps the frame's own generation (aimed by rows p1e1-p1e6, a generation created between the call and the access object, D-0758 (2). NOT killed by p1a12-p1a19 or p1d1-p1d10)", file=C, targets=TG + TC,
         old=STORE_C,
         new='''        ld.frames[fr].generation = generationFrame(ld.frames[fr])  # (the frame's own: no store)
'''),
    dict(id="AGEN-R2 retract/1 keeps the frame's own generation", file=P, targets=TG + TR,
         old=STORE_R,
         new='''        ld.frames[fr].generation = generationFrame(ld.frames[fr])  # (the frame's own: no store)
''',
         equivalent="as AGEN-R1: the frame's generation is the global generation at the call, which pushPredicateAccessObj! reads again "
                    "before any generation is created (src/pl-proc.jl pl_retract1_va); equal values in every case the rows reach"),
]
