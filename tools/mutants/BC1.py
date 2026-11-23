# ORIGINAL: BC1's mutant list; the code is a port of pl-gc.c garbageCollect's entry (`if ( LD->gc.status.blocked || !truePrologFlag(PLFLAG_GC) ) return false`),
# read at the pin 18168e62.
# tools/mutants/BC1.py -- G1-FIX-9 (test_ball_cells.jl D-0029 condition 3 after chunk 8): run by hand with
# `tools/mutate.sh run-in-tree tools/mutants/BC1.py test/core_lang/test_ball_cells.jl -- BC1-S1`.
# BC1-S1: garbageCollect never collects (the entry always returns false). KILL: test_ball_cells.jl's collector-on row (`collections > c0`).
# MEASURED in G1-FIX-10 (D-0971 (5), reference, test_ball_cells.jl alone, the whole failure list of the mutant run): THREE rows fail under BC1-S1:
#   :133 the setup `garbageCollect(...) == BOOLEX_TRUE`, :158 the collector-on row `collections > c0` and :159 `during < 40000 ÷ 4`; the flag-off
#   assertion `collections == c_off` (:150) PASSES under the mutant. So the collector-on row fails on its own account (with the mutant nothing ever
#   collects, whatever the setup does), and the verdict does not rest on :133.
# MEASURED in G1-FIX-9 (why this one and not a safe-point mutant): the loop's collections come from TWO redundant paths, the exception GC point after
#   resumeAfterException (pl-wam.jl, pl-vmi.c:5312-5316) and ensureGlobalSpace's considerGC; killing either alone leaves 1 -> 10 collections (SURVIVED on
#   this file, both verdicts in evidence). Likewise the flag `gc` is tested twice (considerGarbageCollect and garbageCollect): a mutant on garbageCollect's
#   test alone SURVIVES in this file (equivalent end to end here), one on considerGarbageCollect's is caught by test_gc_stats_swipl.jl:235, not by this file.
# TARGETS (audit D-0238): every file that drives a collection through garbageCollect (grep at the tip of wip/g1fix); the hand run used the row's own file only.
# `old` counted EXACTLY once in src/pl-gcdriver.jl; `new` != `old`; no duplicate id.
BC = "test/core_lang/test_ball_cells.jl"
GD = "test/core_lang/test_gc_driver.jl"
GS = "test/core_lang/test_gc_stats_swipl.jl"
SP = "test/core_lang/test_g1gc_safe_points.jl"
SL = "test/core_lang/test_stack_limit.jl"
WS = "test/core_lang/test_g1c_wiring_swipl.jl"
GF = "test/core_lang/test_gc_frames.jl"
TARGETS = [BC, GD, GS, SP, SL, WS, GF]


def m(id, file, old, new, targets):
    return dict(id=id, file=file, old=old, new=new, targets=targets)


MUTANTS = [
    m("BC1-S1", "src/pl-gcdriver.jl",
      "if ld.gc.status.blocked != 0 || !truePrologFlag(ld, PLFLAG_GC)",
      "if true",
      [BC, GD, GS, SP, SL, WS, GF]),
]
