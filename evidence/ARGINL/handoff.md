# ARGINL handoff (writer; edit-only; wip/arginl off main cedc954)

Upstream pin cbf4e1896275. Step: inline arg/3 in a clause body (B_ARG_CF, B_ARG_VF).

## Plan (ordered groups; each one commit)
1. VM codes + table: src/pl-vmi.jl `B_ARG_CF = code(157)`, `B_ARG_VF = code(158)` (appended: numbering keeps
   pl-vmi.c order only up to I_TCALL) + `code_info` rows (pl-vmi.c:1537, 1580). Header "NOT EMITTED" note.
2. Compile: src/pl-comp.jl compileBodyArg3 (pl-comp.c:4494-4527) emits Output_3!; the old NotPortedError is gone.
3. Run loop: src/pl-wam.jl VMI_RUN + labels B_ARG_CF, arg3_fast, arg3_slow, B_ARG_VF (pl-vmi.c:1537-1592);
   `gd.procedures_arg3` (pl-global.jl field + pl-ext.jl `LOOKUPPROC(arg3)`, pl-ext.c:371).
4. Decompile: src/pl-comp.jl decompile cases (pl-comp.c:6582-6592).
5. GC: src/pl-gc.jl clearUninitialisedVarsFrame (pl-gc.c:1405-1408, `setVar(PC[3])`) + the comment at :236.
6. Rows: test/ file from swipl 10.1.19 (generator, driver, .out under evidence/ARGINL), update the two stale pins in
   test/compile/test_body_code_swipl.jl (:1072, :1139).
7. Mutants: tools/mutants/ARGINL.py.
8. docs/architecture.md block + test/static_analysis_manifest.jl entries (LAST, own commits).

## Not written (no infrastructure)
- pl-wam.c put_vm_call cases B_ARG_CF (debugger break description): the kernel has no put_vm_call.
- pl-gc.c mark-phase cases (pl-gc.c:2124-2130): no stack GC in the kernel.

## State
(see below; updated per commit)
