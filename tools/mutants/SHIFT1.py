# ORIGINAL: SHIFT1's mutant list; the code is a port of pl-gc.c grow_stacks' shift counters (:5419-5421, :5472, :5496-5499 at 18168e62) plus the kernel's
# modelled trail size (no swipl-devel counterpart: the trail is a Julia vector).
# tools/mutants/SHIFT1.py -- the mutation battery of G1 E2 (audit D-0966 (2), option (b)): `growStacks!` and `growStacks_trim!` (src/pl-gc.jl) tick
# local_shifts, `_growGlobalStack!` (src/pl-alloc.jl) ticks global_shifts past GLOBAL_INITIAL, `_trail_push!` / `_growTrail!` (src/pl-inline.jl) tick
# trail_shifts past the modelled trail size. NOTHING was run when this list was drafted: the kills below are read off the rows, the CI battery is the verdict.
# Run ONCE, in CI (.github/workflows/mutation.yml). Format: tools/mutate_drive.py's: `id`, `file`, `old` (EXACTLY once), `new`, `targets`, optional `equivalent`.
# Each id names its KILL: SC = test/core_lang/test_shift_counters_swipl.jl (sc1 fresh [0,0,0]; sc2 local; sc3 global; sc4 trail; sc5 trim), GS =
# test/core_lang/test_gc_stats_swipl.jl (`_GS_KERNEL_ZERO`: gs2/gs5 on a fresh engine read 0).
# TARGETS (audit D-0238): every test file that exercises the mutated code: the stacks grow in test_gc_frames.jl (the lshift/gshift/tshift rows wait for the
# counters), test_gc_leak_reset_upstream_swipl.jl (its stack_shifts row), test_stack_limit.jl, test_stack_overflow_swipl.jl and test_local_stack.jl
# (growStacks!, growStacks_trim!), as the E2 design listed them.
# Every `old` was counted EXACTLY once in its file (python3 -I, src.count(old) == 1) at the tip of wip/g1fix-e2 when this file was written (no Julia ran);
# `new` != `old`; no duplicate id. RE-FIT any `old` that `tools/warm.sh fmt` rewraps.
SC = "test/core_lang/test_shift_counters_swipl.jl"
GS = "test/core_lang/test_gc_stats_swipl.jl"
GF = "test/core_lang/test_gc_frames.jl"
LR = "test/core_lang/test_gc_leak_reset_upstream_swipl.jl"
SL = "test/core_lang/test_stack_limit.jl"
SO = "test/core_lang/test_stack_overflow_swipl.jl"
LS = "test/core_lang/test_local_stack.jl"
TARGETS = [SC, GS, GF, LR, SL, SO, LS]       # the union of every mutant's targets (mutate_ci.py plan reads TARGETS)
F = "src/pl-gc.jl"
A = "src/pl-alloc.jl"
I = "src/pl-inline.jl"


def m(id, old, new, targets, file=F, eq=None):
    d = dict(id=id, file=file, old=old, new=new, targets=targets)
    if eq:
        d["equivalent"] = eq
    return d


MUTANTS = [
    # growStacks!: no local_shifts tick on growth (kill: SC sc2 reads `same`)
    m("SHIFT1-L1", "    size != oldsize && (ld.shift_status.local_shifts += 1)",
      "    false && (ld.shift_status.local_shifts += 1)", TARGETS),
    # growStacks_trim!: no local_shifts tick when the local stack shrinks (kill: SC sc5 reads `same`)
    m("SHIFT1-L2", "        new != size && (ld.shift_status.local_shifts += 1)",
      "        false && (ld.shift_status.local_shifts += 1)", TARGETS),
    # _growGlobalStack!: no global_shifts tick (kill: SC sc3 reads `same(20000)`)
    m("SHIFT1-G1", "    n > GLOBAL_INITIAL && (ld.shift_status.global_shifts += 1)",
      "    false && (ld.shift_status.global_shifts += 1)", TARGETS, file=A),
    # _growGlobalStack!: the initial allocation counted as a shift (kill: SC sc1 reads [1,0,0] or more; GS gs2/gs5 not 0)
    m("SHIFT1-G2", "    n > GLOBAL_INITIAL && (ld.shift_status.global_shifts += 1)",
      "    n > 0 && (ld.shift_status.global_shifts += 1)", TARGETS, file=A),
    # _growTrail!: the modelled size grows, the shift is not counted (kill: SC sc4 reads `same`)
    m("SHIFT1-T1", "    ld.shift_status.trail_shifts += 1",
      "    nothing", TARGETS, file=I),
    # _trail_push!: the size is never checked, the trail never shifts (kill: SC sc4 reads `same`)
    m("SHIFT1-T2", "    length(ld.trail) > ld.trail_size && _growTrail!(ld)",
      "    false && _growTrail!(ld)", TARGETS, file=I),
]
