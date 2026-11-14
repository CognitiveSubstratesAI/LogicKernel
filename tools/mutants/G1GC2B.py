# ORIGINAL: G1-GC G1-2b's mutant list; the VM-state provider of the stack collector is a port of pl-gc.c at the pin, the list itself is the kernel's own.
# tools/mutants/G1GC2B.py — the mutation battery of G1-GC step G1-2b: `gc_walk_start_of_vmi!`, `setStartOfVMI` and `get_vmi_state` of src/pl-gcdriver.jl, and
# the two call sites of src/pl-gc.jl (`considerGC`, `pl_garbage_collect`) that pass the provider to `garbageCollect`. NOTHING was run when this list was
# drafted: the kills below are read off the rows of test/core_lang/test_gc_vmi_state.jl, the CI battery is the verdict. Run ONCE, in CI
# (.github/workflows/mutation.yml). Format: tools/mutate_drive.py's (as G1GC6C.py): `id`, `file`, `old` (must occur EXACTLY once), `new`, optional
# `equivalent` and `targets`.
# Each id names its KILL, the testset of test/core_lang/test_gc_vmi_state.jl (GV) that must fail, by the first words of its name:
#   FS = "foreign safe points run: functor/3, =../2 and '$length'/2 collect, the answers stay those of a run without a collection"
#   LA = "live arguments survive a collection at a foreign call: answers, views and the pinned swipl text"
#   PR = "the provider on an open query: frame, choice, lSave, argp, body mode, the argument stack, the guards" (one inner testset per row, `provider: <row>`)
#   WK = "the walk gc_walk_start_of_vmi!: every instruction start and the pc inside it, against the rule table"
#   CR = "a frame no pool owns MUST make the provider throw; a wrong lSave MUST change lTop at the restore"
#   DC = "the decline of a caller without a callback stays; with get_vmi_state the same call collects"
# TARGETS (audit D-0238): the provider is reached by test/core_lang/test_gc_vmi_state.jl (its own rows), and, through `garbageCollect` and `considerGC`, by
#   test_gc_driver.jl and test_g1gc_safe_points.jl (the two strict rows `coll_on > 0` / `on_coll > 0`); the phases it feeds are the rows of test_gc_mark.jl,
#   test_gc_sweep.jl, test_gc_compact.jl and test_gc_trail.jl.
# NOT COVERED by a kill (read off the rows; a lane may add rows): `pl_garbage_collect` is the only caller whose collection is not forced: gv4 of LA is the
#   row (the one program whose only collection is `garbage_collect/0`); the argument-stack entry's `uwrite` bit is a field here and is not read.
# VERDICTS: the CI battery runs one fresh process per mutant and its verdicts are authoritative. A mutant that changes a heap walk may fail with an
#   error (a kill) instead of a failed comparison.
# Every `old` is counted EXACTLY once in its file by `python3 -I ~/code/lk-t27-scratch/oldscan.py G1GC2B` from the repository root;
# `new` != `old`; no duplicate id. RE-FIT any `old` that `tools/warm.sh fmt` rewraps.
GV = "test/core_lang/test_gc_vmi_state.jl"
GD = "test/core_lang/test_gc_driver.jl"
SP = "test/core_lang/test_g1gc_safe_points.jl"
GM = "test/core_lang/test_gc_mark.jl"
GS = "test/core_lang/test_gc_sweep.jl"
GC = "test/core_lang/test_gc_compact.jl"
GT = "test/core_lang/test_gc_trail.jl"
TARGETS = [GV, GD, SP, GM, GS, GC, GT]
D = "src/pl-gcdriver.jl"
G = "src/pl-gc.jl"

def m(id, old, new, file=D, eq=None):
    d = dict(id=id, file=file, old=old, new=new, targets=TARGETS)
    if eq:
        d["equivalent"] = eq
    return d

MUTANTS = [
    # ---- gc_walk_start_of_vmi!: the loop and the rule table
    m("G1GC2B-W1 walk: the instruction that ENDS at pc does not hold it (`next >= pc` -> `>`) (KILL WK: a pc at the start of an instruction names the one before it)",
      "if nxt >= vm.pc",
      "if nxt > vm.pc"),
    m("G1GC2B-W2 walk: a one-word head instruction at depth 0 does not move argp (KILL WK: the hand-pinned argp offsets of w1(f(a,B), c, D))",
      "vm.adepth == 0 && (vm.argp += 1)",
      "vm.adepth == 0 && (vm.argp += 0)"),
    m("G1GC2B-W3 walk: H_VOID_N moves argp by one, not by its operand (KILL WK: the void run of w2)",
      "vm.adepth == 0 && (vm.argp += Int(codes[pc + 1]))",
      "vm.adepth == 0 && (vm.argp += 1)"),
    m("G1GC2B-W4 walk: B_UNIFY_VAR names the argument slot, not the variable slot (KILL WK: argp after a B_UNIFY_VAR of w4)",
      "vm.argp = varFrameP(base, Int(codes[pc + 1]))",
      "vm.argp = argFrameP(base, Int(codes[pc + 1]))"),
    m("G1GC2B-W5 walk: H_FUNCTOR leaves argp0 NULL (KILL WK: argp0 inside the compound of w1)",
      "vm.argp0 = vm.argp",
      "vm.argp0 = 0"),
    m("G1GC2B-W6 walk: B_FUNCTOR does not deepen (KILL WK: adepth inside the body compound of w4)",
      "elseif op == B_FUNCTOR || op == B_LIST\n            vm.adepth += 1",
      "elseif op == B_FUNCTOR || op == B_LIST\n            vm.adepth += 0"),
    m("G1GC2B-W7 walk: the pop to depth 0 keeps argp0 (KILL WK: argp0 after the H_POP of w1)",
      "vm.adepth == 0 && (vm.argp0 = 0)",
      "vm.adepth == 0 && (vm.argp0 = vm.argp0)"),
    m("G1GC2B-W8 walk: I_ENTER does not set in_body (KILL WK, PR: in_body after the I_ENTER of w3 and of bd/1)",
      "elseif op == I_ENTER || op == I_SSU_COMMIT || op == I_SSU_CHOICE\n            vm.in_body = true",
      "elseif op == I_ENTER || op == I_SSU_COMMIT || op == I_SSU_CHOICE\n            vm.in_body = false"),
    m("G1GC2B-W9 walk: a pc past the end names the last instruction (KILL WK: `pc_start_vmi == 0` past the end)",
      "    vm.pc_start_vmi = 0\n    return nothing\nend\n\n# PORT: pl-gc.c setStartOfVMI\n# DIVERGES: `registers",
      "    vm.pc_start_vmi = pc\n    return nothing\nend\n\n# PORT: pl-gc.c setStartOfVMI\n# DIVERGES: `registers"),
    # ---- setStartOfVMI: the guards
    m("G1GC2B-S1 setStartOfVMI: the walk runs over any vector of code (KILL PR: another vector of code finds no VMI)",
      "if pcc === codes",
      "if true"),
    m("G1GC2B-S2 setStartOfVMI: the dcall1 frame is not in the body (KILL PR: dcall1 frame, in_body at once)",
      "if pred === (ld.GD::PL_global_data{T}).procedures_dcall1.definition",
      "if false"),
    m("G1GC2B-S3 setStartOfVMI: a pc of NULL is walked (KILL PR: pc 0 of the clause's code finds no VMI)",
      "(pred.flags & P_FOREIGN) == 0 && vm.pc != 0",
      "(pred.flags & P_FOREIGN) == 0 && true"),
    m("G1GC2B-S4 setStartOfVMI: a foreign predicate's frame is walked (KILL PR: a foreign predicate's frame is not walked)",
      "(pred.flags & P_FOREIGN) == 0 && vm.pc != 0",
      "true && vm.pc != 0"),
    # ---- get_vmi_state: the registers
    m("G1GC2B-P1 provider: the choice is NULL (KILL PR: choice is BFR)",
      "vm.choice = ld.BFR\n    vm.lSave = ld.lTop\n    vm.in_body = false",
      "vm.choice = 0\n    vm.lSave = ld.lTop\n    vm.in_body = false"),
    m("G1GC2B-P2 provider: lSave is one above lTop (KILL PR: lSave is lTop; CR: lTop after the restore)",
      "vm.choice = ld.BFR\n    vm.lSave = ld.lTop\n    vm.in_body = false",
      "vm.choice = ld.BFR\n    vm.lSave = ld.lTop + 1\n    vm.in_body = false"),
    m("G1GC2B-P3 provider: argp is the second argument slot (KILL PR: argp is the frame's first argument slot)",
      "vm.argp = argFrameP(fr.base, 0)\n    vm.argp0 = 0",
      "vm.argp = argFrameP(fr.base, 1)\n    vm.argp0 = 0"),
    m("G1GC2B-P4 provider: the pc of the registers is not read (KILL PR: body rows; the VMI is the I_CALL)",
      "vm.pc = qf.registers_pc.pc",
      "vm.pc = 0"),
    m("G1GC2B-P5 provider: save_argp is always true (KILL PR: the foreign frame's save_argp is false)",
      "vm.save_argp = fr.clause !== nothing",
      "vm.save_argp = true"),
    m("G1GC2B-P6 provider: qlTop without a next_environment is one above lTop (KILL PR: new_args and lNext of the body rows)",
      "qlTop = qf.next_environment != 0 ? ld.frames[qf.next_environment].base : ld.lTop",
      "qlTop = qf.next_environment != 0 ? ld.frames[qf.next_environment].base : ld.lTop + 1"),
    m("G1GC2B-P7 provider: qlTop ignores next_environment (KILL PR: next_environment above: qlTop is that frame's base)",
      "qlTop = qf.next_environment != 0 ? ld.frames[qf.next_environment].base : ld.lTop",
      "qlTop = ld.lTop"),
    m("G1GC2B-P8 provider: a qlTop at the frame itself stays (`<=` -> `<`) (KILL PR: next_environment == frame: qlTop is argFrameP(frame, arity))",
      "if qlTop <= fr.base",
      "if qlTop < fr.base"),
    m("G1GC2B-P9 provider: the end of the arguments is one slot further (KILL PR: next_environment == frame)",
      "qlTop = argFrameP(fr.base, (fr.predicate::Definition{T}).arity)",
      "qlTop = argFrameP(fr.base, (fr.predicate::Definition{T}).arity + 1)"),
    m("G1GC2B-P10 provider: the new arguments are counted one too many (KILL PR: two new arguments above the next frame)",
      "vm.new_args = ap.pos - newbase",
      "vm.new_args = ap.pos - newbase + 1"),
    m("G1GC2B-P11 provider: an argument pointer AT the next frame's arguments counts as new (`>` -> `>=`) (KILL PR: ap == argFrameP(qlTop, 0) holds no new argument)",
      "if ap.pos > newbase",
      "if ap.pos >= newbase"),
    m("G1GC2B-P12 provider: lTop is not raised to the argument pointer (KILL PR: lTop is raised to the argument pointer)",
      "ap.pos > ld.lTop && (ld.lTop = ap.pos)",
      "false && (ld.lTop = ap.pos)"),
    m("G1GC2B-P13 provider: the argument stack is read at its saved height (`>` -> `>=`) (KILL PR: an entry at or below aSave is not read)",
      "if at > ab",
      "if at >= ab"),
    m("G1GC2B-P14 provider: lNext stays NULL (KILL PR: two new arguments above the next frame)",
      "vm.lNext = qlTop",
      "vm.lNext = 0"),
    # ---- the two callers
    m("G1GC2B-C1 considerGC: the safe point passes no provider, the collector declines inside the VM (KILL FS: coll_on >= 1; test_gc_driver.jl and test_g1gc_safe_points.jl strict rows)",
      "garbageCollect(ld, Int(reason); vmi_state_of=get_vmi_state)",
      "garbageCollect(ld, Int(reason))",
      file=G),
    m("G1GC2B-C2 pl_garbage_collect: garbage_collect/0 passes no provider (KILL LA: gv4's collection count rises; DC)",
      "garbageCollect(ld, Int(GC_USER); vmi_state_of=get_vmi_state)",
      "garbageCollect(ld, Int(GC_USER))",
      file=G),
]
