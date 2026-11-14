# ORIGINAL: G1-A's mutant list — no swipl-devel counterpart.
# tools/mutants/G1GC7.py — the mutation battery of G1-GC G1-A: src/pl-gcdriver.jl `clearLocalVariablesFrame` and `setLTopInBody`, and the flag `LD->trim_stack_requested`
# (set in src/pl-alloc.jl `outOfStack!`, cleared first in src/pl-setup.jl `trimStacks!`, read by the driver in src/pl-gcdriver.jl). NOTHING was run when it was drafted: the
# kills below are read off the rows, the CI battery is the verdict.
# Run ONCE, in CI (.github/workflows/mutation.yml; locally: tools/mutate.sh run). Format: tools/mutate_drive.py's (as G1GC6A.py): `id`, `file`,
# `old` (must occur EXACTLY once), `new`, optional `equivalent` and `targets`.
# Each id names its KILL, the row that must fail, in test/core_lang/test_gc_frames.jl (GF); the rows of the first testset are `@testset "frames: <row>"` for the
# named row (the premise rows `premise: ...` guard the others), the other two testsets by their titles:
#   NOQ = "setLTopInBody with no query is a no-op"; TSR = "trim_stack_requested: an overflow sets it, trimStacks! clears it, the driver reads it" (its @test lines are
#   quoted below).
# TARGETS (audit D-0238): every test file that runs the mutated code. clearLocalVariablesFrame is called only by test_gc_frames.jl (the collector's own callers
#   are G1-C/D); setLTopInBody and the vmi-state provider it builds are exercised by test_gc_vmi_state.jl as well; the driver (garbageCollect) runs in test_gc_driver.jl and
#   the whole collection tests; `outOfStack!` and `trimStacks!` run in test_local_stack.jl (the overflow, the shrink). The `TARGETS` variable is the union
#   (mutate_ci.py plan reads it).
# EQUIVALENT mutants: none declared. Every `old` was counted EXACTLY once in its file by a python3 -I script (oldscan.py) at the tip of wip/g1gc-6 when this file was
#   written (no Julia ran); `new` != `old`; no duplicate id. RE-FIT any `old` that `tools/warm.sh fmt` rewraps.
GF = "test/core_lang/test_gc_frames.jl"
GV = "test/core_lang/test_gc_vmi_state.jl"
GD = "test/core_lang/test_gc_driver.jl"
LS = "test/core_lang/test_local_stack.jl"
TARGETS = [GF, GV, GD, LS]                   # the union of every mutant's targets (mutate_ci.py plan reads TARGETS)
FD = "src/pl-gcdriver.jl"
FA = "src/pl-alloc.jl"
FS = "src/pl-setup.jl"


def m(id, old, new, targets=TARGETS, file=FD, eq=None):
    d = dict(id=id, file=file, old=old, new=new, targets=targets)
    if eq:
        d["equivalent"] = eq
    return d


MUTANTS = [
    # ---- clearLocalVariablesFrame
    m("G1GC7-C1 clearLocalVariablesFrame: the clause test is dropped (KILL GF `frames: no clause: nothing is written`: the frame of a NULL clause is read through `clause::ClauseRef`, an error that fails the testset)",
      "    if f.clause !== nothing && (pred.flags & P_FOREIGN) == 0\n",
      "    if (pred.flags & P_FOREIGN) == 0\n"),
    m("G1GC7-C2 clearLocalVariablesFrame: the clause test is negated (KILL GF `frames: clear: every slot from the arity to prolog_vars - 1 is the word 0`, and `clear: the sentinels ...` stays: nothing is written on a clause frame)",
      "    if f.clause !== nothing && (pred.flags & P_FOREIGN) == 0\n",
      "    if f.clause === nothing && (pred.flags & P_FOREIGN) == 0\n"),
    m("G1GC7-C3 clearLocalVariablesFrame: the foreign-predicate test is dropped (KILL GF `frames: a foreign predicate: nothing is written`: atom_length/2 has arity 2, the clause 3 variables, so slot 2 is written)",
      "    if f.clause !== nothing && (pred.flags & P_FOREIGN) == 0\n",
      "    if f.clause !== nothing\n"),
    m("G1GC7-C4 clearLocalVariablesFrame: the foreign-predicate test is negated (KILL GF `frames: clear: every slot from the arity ...`: a clause frame is left alone)",
      "    if f.clause !== nothing && (pred.flags & P_FOREIGN) == 0\n",
      "    if f.clause !== nothing && (pred.flags & P_FOREIGN) != 0\n"),
    m("G1GC7-C5 clearLocalVariablesFrame: the first slot is one too low, an argument is cleared (KILL GF `frames: clear: the arguments are untouched (`i` starts at the arity)`)",
      "        i = pred.arity ",
      "        i = pred.arity - 1 "),
    m("G1GC7-C6 clearLocalVariablesFrame: the first slot is one too high, the first variable is left (KILL GF `frames: clear: every slot from the arity to prolog_vars - 1 is the word 0`)",
      "        i = pred.arity ",
      "        i = pred.arity + 1 "),
    m("G1GC7-C7 clearLocalVariablesFrame: the loop runs one slot too far (KILL GF `frames: clear: the cell above prolog_vars is untouched (`i<slots` stops)`)",
      "        while i < slots ",
      "        while i <= slots "),
    m("G1GC7-C8 clearLocalVariablesFrame: the loop stops one slot early (KILL GF `frames: clear: every slot from the arity to prolog_vars - 1 is the word 0`)",
      "        while i < slots ",
      "        while i < slots - 1 "),
    m("G1GC7-C9 clearLocalVariablesFrame: a non-zero word is written (KILL GF `frames: clear: every slot from the arity to prolog_vars - 1 is the word 0`)",
      "            ld.slots[sp + 1] = word(0)\n",
      "            ld.slots[sp + 1] = word(1)\n"),
    m("G1GC7-C10 clearLocalVariablesFrame: the cell below the slot is written (KILL GF `frames: clear: every slot from the arity ...`, `clear: the arguments are untouched`)",
      "            ld.slots[sp + 1] = word(0)\n",
      "            ld.slots[sp] = word(0)\n"),
    m("G1GC7-C11 clearLocalVariablesFrame: the slot pointer is not advanced, one cell is written twice (KILL GF `frames: clear: every slot from the arity to prolog_vars - 1 is the word 0`)",
      "            sp += 1\n",
      "            sp += 0\n"),
    # ---- setLTopInBody
    m("G1GC7-S1 setLTopInBody: the VM state is left unbuilt, lTop stays unraised (KILL GF `frames: setLTopInBody: returns nothing, lTop is raised to the argument pointer`, `setLTopInBody: twice ...`, `a higher argument pointer raises it further`)",
      "    gc_get_vmi_state(ld, ld.query, gc_vmi_state_of) ",
      "    nothing "),
    m("G1GC7-S2 setLTopInBody: the state is restored, lTop is put back (KILL GF `frames: setLTopInBody: returns nothing, lTop is raised ...`; `a lower one never lowers it (restore_vmi_state is not called)`)",
      "    gc_get_vmi_state(ld, ld.query, gc_vmi_state_of) ",
      "    gc_restore_vmi_state(ld, gc_get_vmi_state(ld, ld.query, gc_vmi_state_of)::vm_state) "),
    m("G1GC7-S3 setLTopInBody: the wrong frame, no query is passed (KILL GF `frames: setLTopInBody: returns nothing, lTop is raised ...`: the fallback arm of gc_get_vmi_state leaves lTop)",
      "    gc_get_vmi_state(ld, ld.query, gc_vmi_state_of) ",
      "    gc_get_vmi_state(ld, 0, gc_vmi_state_of) "),
    m("G1GC7-S4 setLTopInBody: no state provider, the in-body arm is never taken (KILL GF `frames: setLTopInBody: returns nothing, lTop is raised ...`)",
      "    gc_get_vmi_state(ld, ld.query, gc_vmi_state_of) ",
      "    gc_get_vmi_state(ld, ld.query, nothing) "),
    # ---- trim_stack_requested
    m("G1GC7-T1 the driver ignores the flag: trimStacks!(ld, false) (KILL TSR `@test lsize(ld) < big` after setting the flag: the grown stack keeps its size)",
      "    trimStacks!(ld, ld.trim_stack_requested) ",
      "    trimStacks!(ld, false) "),
    m("G1GC7-T2 the driver always resizes: trimStacks!(ld, true) (KILL TSR `@test lsize(ld) == big` with the flag clear: the stack shrinks)",
      "    trimStacks!(ld, ld.trim_stack_requested) ",
      "    trimStacks!(ld, true) "),
    m("G1GC7-T3 outOfStack! does not set the flag (KILL TSR `@test ld.trim_stack_requested && ld.outofstack` after the overflow)",
      "    ld.trim_stack_requested = true ",
      "    ld.trim_stack_requested = false ",
      file=FA),
    m("G1GC7-T4 trimStacks! does not clear the flag first (KILL TSR `@test !ld.trim_stack_requested` after resumeAfterException, after trimStacks!(ld, false), and `trimStacks clears it whatever its argument`)",
      "    ld.trim_stack_requested = false ",
      "    ld.trim_stack_requested = ld.trim_stack_requested ",
      file=FS),
]
