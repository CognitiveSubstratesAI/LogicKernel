# ORIGINAL: ALLOC1's mutant list; the code is a port of pl-vmi.c I_ENTER's signal test (:1947-2055 at the pin 18168e62, the `is_signalled(LD)` arm) and of
# pl-gc.c get_vmi_state (the VM state of a query inside the VM), with the kernel's reuse of the collection's record `ld.gc.vm` (ALLOC-FIX d, audit D-0971 (4)).
# tools/mutants/ALLOC1.py -- ALLOC-FIX (audit D-0971 (1)(b), (4)): two mutants, run by hand with `tools/mutate.sh run-in-tree tools/mutants/ALLOC1.py <targets>`.
# ALLOC1-A1: an allocation planted on the NON-signal path of I_ENTER's `is_signalled` test (`repr` builds a String; behaviour unchanged). It proves the
#   SPAN_CALLEE_EXEMPT :cold entry for handleSignals (test/static_analysis_manifest.jl) exempts the signal arm only. KILL: test/test_static_analysis.jl's row
#   "AllocCheck: the call path's labels allocate nothing" (reference).
# ALLOC1-V1: get_vmi_state hands out the record `ld.gc.vm` for a PARENT query too (the record of the nested safe point is overwritten while live). KILL:
#   test_gc_vmi_state.jl's row "a nested collection: the parent query's VM state is a fresh object, the live record ld.gc.vm is not overwritten".
# THE STATIC-ANALYSIS TARGET (audit D-0994 (3)): the whole test/test_static_analysis.jl is ~100 min in one process (the unmutated BASELINE took 1727 s
#   against LIMIT_S 1500 and ALLOC1-A1 was TIMEOUT at 1617 s: the first run of this list was VOID), so SA is ONE PART of it, the one that holds the kill row:
#   `sh:tools/mutate_sa_part.sh${IFS}call_path` = LOGICKERNEL_SA_SHARD=7/1000000: the part `call_path` alone (CI's `Static analysis 7/9` holds the same part plus
#   one ninth of the per-entry dispatch and AllocCheck gates; here the per-entry gates analyse the one entry k=7). A target holds no blank (tools/mutate_ci.py
#   plan, `$TARGETS` is word-split by the workflow), so the part name follows `${IFS}`, which `bash -c` expands to the separator. Part -> rows -> mutants:
#   call_path = the testset "AllocCheck: the call path's labels allocate nothing" (test/static_analysis_body.jl, `check_allocs(PL_next_solution_guarded, ...)`,
#   the label spans of I_ENTER ... I_CALLATM): kills ALLOC1-A1 and no other mutant of this list. No other part (aqua, jet_package, dispatch_claims, coverage,
#   argstack_push, leaf_alloc, controls, jet_allowlist) and no per-entry AllocCheck entry (`_SA_NOALLOC`: PL_next_solution_guarded is not marked allocation-free,
#   test/static_analysis_manifest.jl) analyses the run loop's I_ENTER label, so none can kill it.
# TARGETS (audit D-0238): every test file that exercises the mutated code. I_ENTER runs in every file; its allocation is seen by the AllocCheck rows and the
# zero-bytes pins of test_zero_exports.jl. get_vmi_state runs in every collection inside the VM: test_gc_vmi_state.jl, test_gc_driver.jl, test_gc_mark.jl,
# test_gc_sweep.jl, test_gc_compact.jl, test_gc_trail.jl, test_gc_frames.jl, test_g1gc_safe_points.jl. The hand run of ALLOC-FIX-2 used test_static_analysis.jl
# (the whole file) and test_gc_vmi_state.jl; this list's SA is the part `call_path` of it (above). ALLOC1-V1 reaches no static-analysis row (a runtime
# record, not an allocation or dispatch site), so its targets name none.
# Every `old` was counted EXACTLY once in its file (python3 -I, src.count(old) == 1) at the tip of wip/g1fix-alloc; `new` != `old`; no duplicate id.
SA = "sh:tools/mutate_sa_part.sh${IFS}call_path"
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
    m("ALLOC1-A1 an allocation on the non-signal path of I_ENTER's is_signalled test (aimed by the static-analysis part call_path, the row AllocCheck: the call path's labels allocate nothing, and the zero-bytes pins of test_zero_exports.jl)", "src/pl-wam.jl",
      "    if is_signalled(ld)\n        @SAVE_REGISTERS(QID)\n        DEF = getProcDefinedDefinition",
      "    if is_signalled(ld) || isempty(repr(DEF.flags))\n        @SAVE_REGISTERS(QID)\n        DEF = getProcDefinedDefinition",
      [SA, ZE]),
    m("ALLOC1-V1 get_vmi_state hands out ld.gc.vm for a parent query too (aimed by test_gc_vmi_state.jl, the row a nested collection: the parent query's VM state is a fresh object)", "src/pl-gcdriver.jl",
      "    vm = qi == ld.query ? ld.gc.vm : vm_state()\n",
      "    vm = ld.gc.vm\n",
      [VS, DR, MK, SW, CP, TR, GF, SP]),
]
