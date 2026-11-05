# ORIGINAL: ENG2a's mutant list (the release of the frozen region scans the global variables' values; audit D-0411); its
# counterpart is the kernel's `_release_frozen!` (src/pl-inline.jl), the stand-in for pl-gc.c's collector until G1.
# tools/mutants/ENG2A.py — the mutation battery of ENG2a, run ONCE, in CI (.github/workflows/mutation.yml; locally:
# tools/mutate_ci.py one). Format: tools/mutate_drive.py's (as MOD3b.py): `id`, `file`, `old` (must occur EXACTLY once),
# `new`, optional `equivalent` and `targets`. Killed by test/core_lang/test_ball_cells.jl (the condition-3 rows and the
# ENG2a rows (1)-(4), named in each id's KILL) and test/core_lang/test_stack_limit.jl (the resource_error count).
# NOT LISTED (each with its reason):
#   * the gate `if ld.gvar_grefs > 0` around the scan: with no value on the global stack every table word is an atom or a
#     small integer, `_global_pos` answers 0 for each and the scan answers 0 <= lim: the scan decides as the gate does.
#   * `_global_pos`'s branches: the slot check's reading of a word since e5, moved into a function unchanged (the
#     condition-2 row of test_ball_cells.jl and test_attvar_words.jl's direct call cover the slot check).
# TARGETS (audit D-0238): `_release_frozen!` runs at the end of every outermost query; the files that exercise its
# global-variable path on a booted copy are the step's own file, test_stack_limit.jl (a load sets values), test_gvar_swipl.jl
# (values across queries), test_query_answers.jl, test_attvar_words.jl (the direct call), and G1d's throw files.
TB = ["test/core_lang/test_ball_cells.jl"]
TF = TB + [
    "test/core_lang/test_stack_limit.jl", "test/core_lang/test_gvar_swipl.jl", "test/foreign/test_query_answers.jl",
    "test/core_lang/test_attvar_words.jl", "test/core_lang/test_exception.jl", "test/core_lang/test_catch_swipl.jl",
    "test/core_lang/test_cleanup_swipl.jl", "test/core_lang/test_findall_swipl.jl", "test/foreign/test_query.jl"
]
TARGETS = TF
I = "src/pl-inline.jl"
MUTANTS = [
    dict(id="ENG2A-M1 the old early return while any global variable is on the stack: every ball's region kept (KILL ball_cells condition 3, ENG2a (2); stack_limit's 10 resource_error rows)",
         file=I, targets=TF,
         old="(ld.frozen_bar == 0 || ld.query != 0 || ld.exception_term != 0) && return nothing",
         new="(ld.frozen_bar == 0 || ld.query != 0 || ld.exception_term != 0 || ld.gvar_grefs > 0) && return nothing"),
    dict(id="ENG2A-M2 the scan ignores the values: the region is released under a live value (KILL ENG2a (1), (3))",
         file=I, targets=TF,
         old="hi = max(hi, _global_pos(ld, w))",
         new="hi = max(hi, 0)"),
    dict(id="ENG2A-M3 the scan compares the wrong end: a value AT the target keeps the region (KILL ENG2a (4))",
         file=I, targets=TF,
         old="_gvar_reach(ld) > lim && return nothing",
         new="_gvar_reach(ld) >= lim && return nothing"),
    dict(id="ENG2A-M4 the open foreign frames are not read: a value between a frame's mark and the target is cut by the frame's discard (KILL ENG2a (3))",
         file=I, targets=TF,
         old="lim = min(lim, ld.fliframes[f].mark.globaltop)",
         new="lim = lim"),
    dict(id="ENG2A-M5 the base frame is read too: its mark (global position 0) lowers the limit to 0 and every ball is kept (KILL ball_cells condition 3, ENG2a (2); stack_limit's resource_error rows)",
         file=I, targets=TF,
         old="for f in 2:(ld.nfliframes)",
         new="for f in 1:(ld.nfliframes)"),
]
