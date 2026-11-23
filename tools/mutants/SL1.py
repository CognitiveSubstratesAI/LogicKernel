# ORIGINAL: SL1's mutant list; the code is a port of pl-copyterm.c copy_term_refs' retry (:847 at the pin 18168e62: makeMoreStackSpace(..., ALLOW_SHIFT|ALLOW_GC),
# pl-gc.c:4622-4672) and of pl-gc.c:3812-3817 clearLocalVariablesFrame's foreign arm (no write for a foreign predicate).
# tools/mutants/SL1.py -- G1-FIX-8 (audit D-0969 (1), (3)): two mutants, run by hand with `tools/mutate.sh run-in-tree tools/mutants/SL1.py <targets>`.
# SL1-R1: copy_term_refs asks makeMoreStackSpace for ALLOW_SHIFT only: after a failed copy no garbageCollect, no retry. KILL: test_stack_limit.jl's testset
#   "f1b: copy_term_refs one cell short, garbage left in place: a collection, the retry fits" (ok == false there).
# SL1-F1: clearLocalVariablesFrame clears the slots of a FOREIGN predicate's frame too. KILL: test_gc_frames.jl's row "a foreign predicate: nothing is written".
# TARGETS (audit D-0238): every file that calls copy_term_refs (grep at the tip of wip/g1fix) and the one that clears frames. The hand runs of G1-FIX-8 used the
# row's own file only (test_stack_limit.jl for R1, test_gc_frames.jl for F1).
# Every `old` was counted EXACTLY once in its file (grep -c at the tip of wip/g1fix); `new` != `old`; no duplicate id.
SL = "test/core_lang/test_stack_limit.jl"
GF = "test/core_lang/test_gc_frames.jl"
CC = "test/core_lang/test_copyterm_cells.jl"
WS = "test/core_lang/test_g1c_wiring_swipl.jl"
SP = "test/core_lang/test_g1gc_safe_points.jl"
TARGETS = [SL, GF, CC, WS, SP]


def m(id, file, old, new, targets):
    return dict(id=id, file=file, old=old, new=new, targets=targets)


MUTANTS = [
    m("SL1-R1", "src/pl-copyterm.jl",
      "makeMoreStackSpace(ld, GLOBAL_OVERFLOW, ALLOW_SHIFT | ALLOW_GC) || return false",
      "makeMoreStackSpace(ld, GLOBAL_OVERFLOW, ALLOW_SHIFT) || return false",
      [SL, CC, WS, SP]),
    m("SL1-F1", "src/pl-gcdriver.jl",
      "if f.clause !== nothing && (pred.flags & P_FOREIGN) == 0",
      "if f.clause !== nothing",
      [GF]),
]
