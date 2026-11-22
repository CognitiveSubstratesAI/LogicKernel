# ORIGINAL: ALLOC1's mutant list; the code is a port of pl-vmi.c I_ENTER's signal test (:1947-2055 at the pin 18168e62, the `is_signalled(LD)` arm) and of
# pl-gc.c get_vmi_state (the VM state of a query inside the VM), with the kernel's reuse of the collection's record `ld.gc.vm` (ALLOC-FIX d, audit D-0971 (4)).
# tools/mutants/ALLOC1.py -- ALLOC-FIX (audit D-0971 (1)(b), (4)): two mutants, run by hand with `tools/mutate.sh run-in-tree tools/mutants/ALLOC1.py <targets>`.
# ALLOC1-A1: an allocation planted on the NON-signal path of I_ENTER's `is_signalled` test (`repr` builds a String; behaviour unchanged). It proves the
#   SPAN_CALLEE_EXEMPT :cold entry for handleSignals (test/static_analysis_manifest.jl) exempts the signal arm only. KILL: test/test_static_analysis.jl's row
#   "AllocCheck: the call path's labels allocate nothing" (reference).
# ALLOC1-V1: get_vmi_state hands out the record `ld.gc.vm` for a PARENT query too (the record of the nested safe point is overwritten while live). KILL:
#   test_gc_vmi_state.jl's row "a nested collection: the parent query's VM state is a fresh object, the live record ld.gc.vm is not overwritten".
# TARGETS (audit D-0238): every test file that exercises the mutated code. I_ENTER runs in every file; its allocation is seen by the AllocCheck rows and the
# zero-bytes pins of test_zero_exports.jl. get_vmi_state runs in every collection inside the VM: test_gc_vmi_state.jl, test_gc_driver.jl, test_gc_mark.jl,
# test_gc_sweep.jl, test_gc_compact.jl, test_gc_trail.jl, test_gc_frames.jl, test_g1gc_safe_points.jl. The hand run of ALLOC-FIX-2 used test_static_analysis.jl
# and test_gc_vmi_state.jl.
# Every `old` was counted EXACTLY once in its file (python3 -I, src.count(old) == 1) at the tip of wip/g1fix-alloc; `new` != `old`; no duplicate id.
SA = "test/test_static_analysis.jl"
ZE = "test/core_lang/test_zero_exports.jl"
VS = "test/core_lang/test_gc_vmi_state.jl"
DR = "test/core_lang/test_gc_driver.jl"
MK = "test/core_lang/test_gc_mark.jl"
SW = "test/core_lang/test_gc_sweep.jl"
CP = "test/core_lang/test_gc_compact.jl"
TR = "test/core_lang/test_gc_trail.jl"
GF = "test/core_lang/test_gc_frames.jl"
SP = "test/core_lang/test_g1gc_safe_points.jl"
TARGETS = [SA, ZE, VS, DR, MK, SW, CP, TR, GF, SP]


def m(id, file, old, new, targets):
    return dict(id=id, file=file, old=old, new=new, targets=targets)


MUTANTS = [
    m("ALLOC1-A1", "src/pl-wam.jl",
      "    if is_signalled(ld)\n        @SAVE_REGISTERS(QID)\n        DEF = getProcDefinedDefinition",
      "    if is_signalled(ld) || isempty(repr(DEF.flags))\n        @SAVE_REGISTERS(QID)\n        DEF = getProcDefinedDefinition",
      [SA, ZE]),
    m("ALLOC1-V1", "src/pl-gcdriver.jl",
      "    vm = qi == ld.query ? ld.gc.vm : vm_state()\n",
      "    vm = ld.gc.vm\n",
      [VS, DR, MK, SW, CP, TR, GF, SP]),
]
