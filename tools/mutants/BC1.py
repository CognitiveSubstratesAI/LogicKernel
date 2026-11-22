# ORIGINAL: BC1's mutant list; the code is a port of pl-gc.c considerGarbageCollect (`if ( truePrologFlag(PLFLAG_GC) )`) and f_ensureStackSpace's
# ALLOW_GC arm (pl-gc.c:4707-4719), read at the pin 18168e62.
# tools/mutants/BC1.py -- G1-FIX-9 (test_ball_cells.jl D-0029 condition 3 after chunk 8): run by hand with
# `tools/mutate.sh run-in-tree tools/mutants/BC1.py test/core_lang/test_ball_cells.jl -- BC1-F1`.
# BC1-F1: considerGarbageCollect ignores the flag `gc`. KILL: test_ball_cells.jl's `collections == c_off` row (the baseline loop runs with the flag off).
# BC1-S1: the safe point never collects (considerGC returns false). KILL: test_ball_cells.jl's collector-on row (`collections > c0`).
# TARGETS (audit D-0238): every file that drives a collection through these two functions (grep at the tip of wip/g1fix); the hand run used the row's own file only.
# Every `old` was counted EXACTLY once in src/pl-gc.jl (grep -c); `new` != `old`; no duplicate id.
BC = "test/core_lang/test_ball_cells.jl"
GD = "test/core_lang/test_gc_driver.jl"
GS = "test/core_lang/test_gc_stats_swipl.jl"
SP = "test/core_lang/test_g1gc_safe_points.jl"
SL = "test/core_lang/test_stack_limit.jl"
WS = "test/core_lang/test_g1c_wiring_swipl.jl"
TARGETS = [BC, GD, GS, SP, SL, WS]


def m(id, file, old, new, targets):
    return dict(id=id, file=file, old=old, new=new, targets=targets)


MUTANTS = [
    m("BC1-F1", "src/pl-gc.jl",
      "if truePrologFlag(ld, PLFLAG_GC)",
      "if true",
      [BC, GD, GS]),
    m("BC1-S1", "src/pl-gc.jl",
      "(flags & ALLOW_GC) == 0 && return false",
      "return false",
      [BC, SP, SL, WS, GD]),
]
