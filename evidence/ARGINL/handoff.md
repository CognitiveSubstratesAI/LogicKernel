# ARGINL handoff (writer; edit-only; wip/arginl off main cedc954)

Upstream pin cbf4e1896275. Step: inline arg/3 in a clause body (B_ARG_CF, B_ARG_VF). Agent 1 stopped at the
150k cap after group 5 (hook error dumps ate the context: avoid recursive greps over src/ and test/, name files).

## Committed on wip/arginl (all edit-only, nothing run)
- fec54f1 plan (this file)
- e341e71 src/pl-vmi.jl: `B_ARG_CF = code(157)`, `B_ARG_VF = code(158)`, codeTable rows (VIF_BREAK, 3 operands,
  CA1_INTEGER,CA1_VAR,CA1_FVAR / CA1_VAR,CA1_VAR,CA1_FVAR), header notes.
- 9de5a18 src/pl-comp.jl compileBodyArg3 emits Output_3! (isFirstVarSet! on the third variable first, as c:4515);
  the integer operand is `reinterpret(code, int64_value(a1))` (as A_ADD_FC's).
- 2e40227 src/pl-wam.jl: VMI_RUN += B_ARG_CF, B_ARG_VF; labels B_ARG_CF, arg3_fast, arg3_slow, B_ARG_VF (after
  B_NEQ_VC), registers a3_idx (slot or 0 for NULL), a3_ai, a3_term, a3_arg (1-based slots); fast path uses
  `_deref_loc`, `arityFunctor`, `_slot_link_loc!`, `truePrologFlag(ld, PLFLAG_VMI_BUILTIN)`; slow path as
  `debug_equals2` (`_slot_new_var!`, `_slot_copy!`, `pushFrame!`, `setNextFrameFlags`, `@goto normal_call`).
  Also src/pl-global.jl field `procedures_arg3` (after procedures_dwakeup1, constructor arg added) and
  src/pl-ext.jl `LOOKUPPROC(arg3)` in setBuiltinPredicateProperties! (pl-global.jl changed => alloc pins x3 owed).
- c223c4a src/pl-comp.jl decompileBodyNoShift: B_ARG_CF/B_ARG_VF cases (c:6582-6592).
- 8678cfc src/pl-gc.jl clearUninitialisedVarsFrame: setVar of codes[pc+3] (pl-gc.c:1405-1408); comment fixed.

## Left (next agent, in this order)
6. Stale pins in test/compile/test_body_code_swipl.jl (read lines ~1090-1145 first): line 1116
   `_BC_IS_REFUSED` drops "b_arg_cf","b_arg_vf"; line ~1139 the refusal loop drops "B_ARG_CF","B_ARG_VF"; the
   emitted-family list (~1143) gains "b_arg_cf","b_arg_vf"; the comment at 1114. Cells ab1.. (1072-1095) already
   hold swipl's instruction names. test/core_lang/test_attvar_wakeup.jl:1123 has a comment saying arg/3 with
   unbound args is not ported (read, reword positively if stale). Run the stale-pin grep of the playbook on named
   files only: test/compile/*.jl, test/core_lang/test_at_body_swipl.jl.
   Then the NEW oracle rows file (generator + driver + .out via swipl 10.1.19, models: evidence/MOD5b, evidence/MOD6,
   test/core_lang/test_at_body_swipl.jl first ~80 lines): clause bodies `p(I,T,X) :- arg(I,T,X0), ...` over: first
   arg var/bound x third var/bound(seen, hence a plain call) x second non-compound/var/cyclic x index 0/negative/
   too large/bignum/atom x `set_prolog_flag(vmi_builtin,false)` (flag registered at src/os/pl-prologflag.jl:1706).
   Also `clause/2` / `listing` read-back of such a clause (decompile) and the nondeterministic case (var index
   enumerates: arg(I,f(a,b),X) with I a SEEN variable that is unbound goes the slow route -> arg/3 backtracks).
7. tools/mutants/ARGINL.py (format of tools/mutants/MOD3b.py; >= 10 mutants: compile emits CF<->VF, drops
   isFirstVarSet!, `ai > 0` -> `>= 0`, `<= arity` -> `< arity`, link into wrong slot, vmi_builtin test dropped,
   slow route index copy swapped, `+ ai` off by one, decompile operand order, gc setVar index; TARGETS = the new rows
   file + test/compile/test_body_code_swipl.jl + the decompile/clause tests; every `old` exactly once).
8. docs/architecture.md block (replace the lines saying B_ARG_* is refused: lines ~3973, ~4053, ~6186 mention it) and
   test/static_analysis_manifest.jl: no new function except none (compileBodyArg3 already at line 480; no new method) -
   check that nothing is needed; DISPATCH_MANIFEST generated part may list `procedures_arg3`-related nothing.
   Each in its own commit, appended blocks only. Do NOT regenerate docs/port_inventory.md (its `declared` column for
   B_ARG_CF/B_ARG_VF rows 464-465 turns on at the gate's `warm.sh inventory`).

## Not written (no infrastructure)
- pl-wam.c put_vm_call cases B_ARG_CF (debugger break description, c:1190): the kernel has no put_vm_call.
- pl-gc.c mark-phase cases (pl-gc.c:2124-2130): no stack GC in the kernel.

## Flags for the audit
- DIVERGES (representation only): no `globaliseVar` on the index/compound slots (a slot is never an unbound variable,
  decision 2; the variable dereferences to a cell, no compound, so the slow route raises the instantiation error as
  upstream's); B_ARG_VF hands the index SLOT to arg3_slow in the not-tagged-int case and in the fast-failure case
  (upstream hands the dereferenced cell: same word).
- A `$expr/n` compound (kernel-only) is read by arityFunctor as pl_arg3_va reads it: the same.
- Tier 1 (pl-comp, pl-wam, pl-vmi, pl-gc) plus pl-global.jl: battery + alloc pins x3 at the gate.

## Gate agent must run (order, playbook)
inventory (commit the regenerated docs/port_inventory.md), fmt (format committed files through `warm.sh send`),
check (incl. Pkg.test-way for changed test files, one at a time), JET/Aqua pre-check, rows x3, test_type_discipline,
the mutants branch, branch-gate, term grep, alloc pins x3, push gate/<fresh name> + mutants/ARGINL at the same SHA.
Unverified: nothing here was parsed or run (no daemon). First suspects if a type test fails: a3_ai Int64 vs Int in
`a3_ai <= a3_arity` (fine), the Procedure field order in the PL_global_data constructor (positional).
