# ORIGINAL: ENG2's mutant list (the release of the frozen region reads each open foreign frame's own term references, not
# every slot below lTop; audit D-0435 option (a)); its counterpart is the kernel's `_release_frozen!` (src/pl-inline.jl), the
# stand-in for pl-gc.c's collector until G1, whose `mark_term_refs` (:1016-1055) reads the same references.
# tools/mutants/ENG2.py — the mutation battery of ENG2, run ONCE, in CI (.github/workflows/mutation.yml; locally:
# tools/mutate_ci.py one). Format: tools/mutate_drive.py's (as ENG2A.py): `id`, `file`, `old` (must occur EXACTLY once),
# `new`, optional `equivalent` and `targets`. Killed by test/core_lang/test_ball_cells.jl: the condition-2 row and the ENG2
# rows (1)-(3), named in each id's KILL as measured by hand on the warm daemon (reference type), one mutant at a time.
# NOT LISTED (each with its reason):
#   * the frame-mark check and the ENG2a limit: unchanged by ENG2 (ENG2A.py's M4/M5 and ball_cells' condition 3 cover them).
#   * `_global_pos`: unchanged, ENG2A.py's NOT LISTED line.
# TARGETS (audit D-0238): the reference scan runs at every outermost CLOSE that lowers gTop (a throw before it, or a ball
# frozen by a nested query): ENG2A.py's files (the throw paths, the booted copy's global variables), test_qlf_swipl.jl (the
# R-B row: a close after an exception on the unbooted database) and test_firstboot_swipl.jl (the `$initialise` runs, whose
# query_loop frame header first hit the old scan).
TB = ["test/core_lang/test_ball_cells.jl"]
TF = TB + [
    "test/core_lang/test_stack_limit.jl", "test/core_lang/test_gvar_swipl.jl", "test/foreign/test_query_answers.jl",
    "test/core_lang/test_attvar_words.jl", "test/core_lang/test_exception.jl", "test/core_lang/test_catch_swipl.jl",
    "test/core_lang/test_cleanup_swipl.jl", "test/core_lang/test_findall_swipl.jl", "test/foreign/test_query.jl",
    "test/files/test_qlf_swipl.jl", "test/core_lang/test_firstboot_swipl.jl"
]
TARGETS = TF
I = "src/pl-inline.jl"
MUTANTS = [
    dict(id="ENG2-M1 the old scan: every slot below lTop, a frame header's old words included (KILL ball_cells ENG2 (1))",
         file=I, targets=TF,
         old="for n in 0:(f.size - 1)",
         new="for n in (-SIZEOF_FLIFRAME - f.base):(ld.lTop - f.base - SIZEOF_FLIFRAME - 1)"),
    dict(id="ENG2-M2 the header is read instead of the references (KILL ball_cells condition 2, ENG2 (2))",
         file=I, targets=TF,
         old="r = refFliP(f.base, n)",
         new="r = f.base + n"),
    dict(id="ENG2-M3 only the innermost frame: the walk stops after fli_context (KILL ball_cells ENG2 (2))",
         file=I, targets=TF,
         old="fr = f.parent",
         new="fr = 0"),
    dict(id="ENG2-M4 the last reference of each frame is missed (KILL ball_cells condition 2, ENG2 (2))",
         file=I, targets=TF,
         old="for n in 0:(f.size - 1)",
         new="for n in 0:(f.size - 2)"),
    dict(id="ENG2-M5 the slot one below each reference is read (position for slot index; KILL ball_cells condition 2, ENG2 (2))",
         file=I, targets=TF,
         old="p = _global_pos(ld, ld.slots[r + 1])",
         new="p = _global_pos(ld, ld.slots[r])"),
    dict(id="ENG2-M6 the boundary: a reference AT the target refused (KILL ball_cells 'as swipl' and ENG2 (1): a reference at the target, also ENG2 (3))",
         file=I, targets=TF,
         old="p > target && error(",
         new="p >= target && error("),
    dict(id="ENG2-M7 the walk starts at the base frame, not fli_context (KILL ball_cells condition 2, ENG2 (2))",
         file=I, targets=TF,
         old="fr = ld.fli_context                         # live term references",
         new="fr = 1                         # live term references"),
    dict(id="ENG2-M8 the reference check removed: a live reference above the target is cut (KILL ball_cells condition 2, ENG2 (2))",
         file=I, targets=TF,
         old="p > target && error(",
         new="false && error("),
]
